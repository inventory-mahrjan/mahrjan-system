-- =====================================================================
-- MAHRJAN SYSTEM - WAREHOUSE: PRODUCTION & CLEANING (CREATE)
-- Same rules as the current van-sales app / production sheets (v13):
--  * Batch no MGAZ-P-0001 (production) / MGAZ-C-0001 (cleaning), MGT-... for Ajman
--  * Shift: DAY 05:00-16:59, NIGHT 17:00-04:59; work date = date the shift started
--  * Supervisor on duty = ACCOUNTANT / RECEIVER of the branch (or both branches)
--  * Packing staff = staff with role PACKER
--  * Production issue: raw egg + tray/lid + label from the finished good's bill of materials
--  * Production return: FG packs, broken, waste, material waste, counted balance;
--    difference = counted - (issued - used - broken - waste), reason required
--  * Cleaning issue: finished goods (packs); return: good / near expiry / broken / waste per raw egg,
--    reusable packing material (the rest is material waste); difference needs a reason
--  * Quantities: finished goods in packs, eggs and material in pieces
-- =====================================================================
begin;

create table public.wh_batches (
  id               bigint generated always as identity primary key,
  branch_id        bigint not null references public.branches(id),
  batch_no         text not null unique,
  process          text not null check (process in ('PRODUCTION','CLEANING')),
  work_date        date not null,
  shift            text not null check (shift in ('DAY','NIGHT')),
  status           text not null default 'ISSUED' check (status in ('ISSUED','CLOSED','CANCELLED')),
  staff_ids        bigint[] not null,
  issued_at        timestamptz not null default now(),
  issued_by        bigint not null references public.staff(id),   -- supervisor on duty
  returned_at      timestamptz,
  received_by      bigint references public.staff(id),
  issued_egg_pcs   numeric(12,2) not null default 0,
  fg_packs         numeric(12,2),
  good_egg_pcs     numeric(12,2),
  near_pcs         numeric(12,2),
  broken_pcs       numeric(12,2),
  waste_pcs        numeric(12,2),
  balance_egg_pcs  numeric(12,2),
  egg_diff         numeric(12,2),
  mat_diff         numeric(12,2),
  hours            numeric(8,2),
  beyond_hours     numeric(8,2),
  output_per_staff_hour numeric(10,1),
  cancel_reason    text,
  created_by       uuid default auth.uid(),
  updated_at       timestamptz,
  updated_by       uuid
);
create index wh_batches_day_idx on public.wh_batches (branch_id, work_date);

create table public.wh_lines (
  id          bigint generated always as identity primary key,
  batch_id    bigint not null references public.wh_batches(id),
  slip        text not null check (slip in ('I1','R1')),
  line_type   text not null check (line_type in ('ISSUE RAW','ISSUE MATERIAL','ISSUE FG','FG','BROKEN','WASTE',
                'MATERIAL WASTE','BALANCE','GOOD','NEAR EXPIRY','CHECK','MATERIAL REUSABLE')),
  for_item_id bigint references public.items(id),     -- the finished good the line belongs to
  item_id     bigint not null references public.items(id),
  qty         numeric(12,2) not null,                 -- packs for FG, pieces for egg / material
  egg_pcs     numeric(12,2) not null default 0,
  calculated  numeric(12,2),
  difference  numeric(12,2),
  reason      text,
  exp_date    date,
  origin      text,
  created_at  timestamptz not null default now(),
  created_by  uuid default auth.uid()
);
create index wh_lines_batch_idx on public.wh_lines (batch_id);

create trigger trg_wh_batches_upd before update on public.wh_batches for each row execute function public.set_updated();
create trigger trg_wh_batches_audit after insert or update or delete on public.wh_batches for each row execute function public.audit_row();
alter table public.wh_batches enable row level security;
alter table public.wh_lines enable row level security;
grant select on public.wh_batches, public.wh_lines to authenticated;
create policy read_branch on public.wh_batches for select to authenticated
  using (public.can_branch(branch_id) and public.my_role() in ('ADMIN','ACCOUNTANT','RECEIVER','VIEWER'));
create policy read_by_batch on public.wh_lines for select to authenticated
  using (exists (select 1 from public.wh_batches b where b.id = batch_id));

-- per-pack bill of materials (item_recipe is per carton)
create or replace view public.v_fg_bom with (security_invoker = true) as
select r.fg_item_id, r.raw_item_id as item_id, m.item_type,
       r.qty_per_carton / nullif(f.packs_per_carton, 0) as per_pack
  from public.item_recipe r
  join public.items f on f.id = r.fg_item_id
  join public.items m on m.id = r.raw_item_id
 where r.active;
grant select on public.v_fg_bom to authenticated;

-- ---------------------------------------------------------------------
create or replace function public.wh_check_duty(p_duty bigint, p_branch bigint)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_role(array['ADMIN','RECEIVER','ACCOUNTANT'], p_branch);
  if not exists (select 1 from public.staff where id = p_duty and active and role in ('ACCOUNTANT','RECEIVER')
                  and (branch_id is null or branch_id = p_branch)) then
    raise exception 'Supervisor on duty must be an active ACCOUNTANT or RECEIVER of this branch';
  end if;
end $$;

-- ISSUE. p_lines production: [{"fg_item_id":1,"item_id":20,"qty":360,"exp_date":"2026-12-10","origin":"UAE"}, ...]
--        p_lines cleaning:   [{"fg_item_id":1,"qty":24}, ...]      qty = packs
create or replace function public.wh_issue(p_branch bigint, p_process text, p_duty bigint, p_staff bigint[], p_lines jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_local timestamp := now() at time zone 'Asia/Dubai'; v_work date; v_shift text; v_no text; v_pre text; v_id bigint;
        v_bad text; v_eggs numeric;
begin
  perform public.wh_check_duty(p_duty, p_branch);
  if p_process not in ('PRODUCTION','CLEANING') then raise exception 'Unknown process %', p_process; end if;
  if coalesce(array_length(p_staff,1),0) = 0 then raise exception 'Pick the packing staff.'; end if;
  select string_agg(x::text, ', ') into v_bad from unnest(p_staff) x
   where not exists (select 1 from public.staff s where s.id = x and s.role = 'PACKER' and s.active and (s.branch_id is null or s.branch_id = p_branch));
  if v_bad is not null then raise exception 'Not an active packer of this branch: %', v_bad; end if;

  drop table if exists t_l;
  create temp table t_l on commit drop as
  select (x->>'fg_item_id')::bigint fg, nullif(x->>'item_id','')::bigint it, round(coalesce((x->>'qty')::numeric,0)) qty,
         nullif(x->>'exp_date','')::date exp, nullif(trim(x->>'origin'),'') origin
    from jsonb_array_elements(coalesce(p_lines,'[]')) x where coalesce((x->>'qty')::numeric,0) > 0;
  if not exists (select 1 from t_l) then raise exception 'Enter at least one qty.'; end if;
  if exists (select 1 from t_l t left join public.items i on i.id = t.fg and i.item_type = 'FG' where i.id is null) then
    raise exception 'Not a finished good in the list'; end if;
  if p_process = 'PRODUCTION' and exists (select 1 from t_l t where not exists
       (select 1 from public.v_fg_bom b where b.fg_item_id = t.fg and b.item_id = t.it)) then
    raise exception 'A line is not in the bill of materials of its finished good'; end if;

  v_work  := (v_local - interval '5 hours')::date;
  v_shift := case when extract(hour from v_local) between 5 and 16 then 'DAY' else 'NIGHT' end;
  v_pre   := (select code from public.branches where id = p_branch) || '-' || left(p_process,1) || '-';
  perform pg_advisory_xact_lock(hashtext(v_pre));
  select v_pre || lpad((coalesce(max(substr(batch_no, length(v_pre)+1)::int),0) + 1)::text, 4, '0') into v_no
    from public.wh_batches where batch_no like v_pre || '%';

  insert into public.wh_batches (branch_id, batch_no, process, work_date, shift, staff_ids, issued_by)
  values (p_branch, v_no, p_process, v_work, v_shift, p_staff, p_duty) returning id into v_id;

  if p_process = 'PRODUCTION' then
    insert into public.wh_lines (batch_id, slip, line_type, for_item_id, item_id, qty, egg_pcs, exp_date, origin)
    select v_id, 'I1', case when i.item_type = 'RAW_EGG' then 'ISSUE RAW' else 'ISSUE MATERIAL' end, t.fg, t.it, t.qty,
           case when i.item_type = 'RAW_EGG' then t.qty else 0 end,
           case when i.item_type = 'RAW_EGG' then t.exp end, case when i.item_type = 'RAW_EGG' then t.origin end
      from t_l t join public.items i on i.id = t.it;
  else
    insert into public.wh_lines (batch_id, slip, line_type, for_item_id, item_id, qty, egg_pcs)
    select v_id, 'I1', 'ISSUE FG', t.fg, t.fg, t.qty, t.qty * coalesce(f.pcs_per_pack,0)
      from t_l t join public.items f on f.id = t.fg;
  end if;
  select coalesce(sum(egg_pcs),0) into v_eggs from public.wh_lines where batch_id = v_id;
  update public.wh_batches set issued_egg_pcs = v_eggs where id = v_id;
  return jsonb_build_object('batch_id', v_id, 'batch_no', v_no, 'work_date', v_work, 'shift', v_shift, 'issued_egg_pcs', v_eggs);
end $$;

-- RETURN + CLOSE.
-- production: {"fg":{"<fg id>":packs}, "broken":{"<raw id>":pcs}, "waste":{"<raw id>":pcs}, "mwaste":{"<mat id>":pcs},
--              "counted":{"<item id>":pcs}, "reason":{"<item id>":"text"}}
-- cleaning:   {"good":{"<raw id>":pcs}, "near":{...}, "broken":{...}, "waste":{...}, "reuse":{"<mat id>":pcs}, "reason":{"<raw id>":"text"}}
create or replace function public.wh_return(p_batch bigint, p_duty bigint, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.wh_batches; g jsonb := coalesce(p_data,'{}'); r record; v_need text := ''; v_end timestamptz; v_hrs numeric; v_sc int;
  t_fg numeric := 0; t_fgegg numeric := 0; t_near numeric := 0; t_br numeric := 0; t_ws numeric := 0; t_bal numeric := 0; t_ed numeric := 0; t_md numeric := 0;
begin
  select * into b from public.wh_batches where id = p_batch for update;
  if not found then raise exception 'Batch not found'; end if;
  perform public.wh_check_duty(p_duty, b.branch_id);
  if b.status <> 'ISSUED' then raise exception '% is already %', b.batch_no, lower(b.status); end if;

  if b.process = 'PRODUCTION' then
    -- finished goods
    for r in select key::bigint fg, round(value::numeric) packs from jsonb_each_text(coalesce(g->'fg','{}')) where coalesce(value,'') <> '' and value::numeric > 0 loop
      if not exists (select 1 from public.wh_lines where batch_id = b.id and slip = 'I1' and for_item_id = r.fg) then
        raise exception '% was not issued in %', (select name from public.items where id = r.fg), b.batch_no; end if;
      insert into public.wh_lines (batch_id, slip, line_type, for_item_id, item_id, qty, egg_pcs)
      select b.id, 'R1', 'FG', r.fg, r.fg, r.packs, r.packs * coalesce(pcs_per_pack,0) from public.items where id = r.fg;
      t_fg := t_fg + r.packs;
      t_fgegg := t_fgegg + r.packs * coalesce((select pcs_per_pack from public.items where id = r.fg),0);
    end loop;
    if t_fg = 0 then raise exception 'Enter the finished goods.'; end if;
    -- each issued egg / material: broken, waste, counted balance
    for r in
      with iss as (select item_id, max(line_type) lt, sum(qty) issued from public.wh_lines where batch_id = b.id and slip = 'I1' group by item_id),
           used as (select bom.item_id, sum(f.qty * bom.per_pack) used
                      from public.wh_lines f join public.v_fg_bom bom on bom.fg_item_id = f.for_item_id
                     where f.batch_id = b.id and f.line_type = 'FG' group by bom.item_id)
      select iss.item_id, iss.lt = 'ISSUE RAW' is_egg, iss.issued, coalesce(used.used,0) used, i.name
        from iss left join used on used.item_id = iss.item_id join public.items i on i.id = iss.item_id
    loop
      declare br numeric := case when r.is_egg then round(coalesce((g->'broken'->>r.item_id::text)::numeric,0)) else 0 end;
              ws numeric := round(coalesce((g->(case when r.is_egg then 'waste' else 'mwaste' end)->>r.item_id::text)::numeric,0));
              cnt numeric; calc numeric; df numeric; rs text := nullif(trim(g->'reason'->>r.item_id::text),'');
      begin
        if (g->'counted'->>r.item_id::text) is null or (g->'counted'->>r.item_id::text) = '' then
          raise exception 'Enter the counted balance for %', r.name; end if;
        cnt := round((g->'counted'->>r.item_id::text)::numeric);
        calc := round(r.issued - r.used - br - ws); df := cnt - calc;
        if df <> 0 and rs is null then v_need := v_need || r.name || ', '; end if;
        if br > 0 then insert into public.wh_lines (batch_id, slip, line_type, item_id, qty, egg_pcs) values (b.id,'R1','BROKEN',r.item_id,br,br); end if;
        if ws > 0 then insert into public.wh_lines (batch_id, slip, line_type, item_id, qty, egg_pcs)
                       values (b.id,'R1', case when r.is_egg then 'WASTE' else 'MATERIAL WASTE' end, r.item_id, ws, case when r.is_egg then ws else 0 end); end if;
        insert into public.wh_lines (batch_id, slip, line_type, item_id, qty, egg_pcs, calculated, difference, reason)
        values (b.id,'R1','BALANCE',r.item_id,cnt, case when r.is_egg then cnt else 0 end, calc, df, case when df <> 0 then rs end);
        if r.is_egg then t_br := t_br + br; t_ws := t_ws + ws; t_bal := t_bal + cnt; t_ed := t_ed + df; else t_md := t_md + df; end if;
      end;
    end loop;
  else
    -- cleaning: eggs given per raw egg (FG packs x eggs per pack)
    for r in
      select bom.item_id raw, sum(l.qty * bom.per_pack) given, i.name
        from public.wh_lines l join public.v_fg_bom bom on bom.fg_item_id = l.item_id and bom.item_type = 'RAW_EGG'
        join public.items i on i.id = bom.item_id
       where l.batch_id = b.id and l.line_type = 'ISSUE FG' group by bom.item_id, i.name
    loop
      declare gd numeric := round(coalesce((g->'good'->>r.raw::text)::numeric,0)); nr numeric := round(coalesce((g->'near'->>r.raw::text)::numeric,0));
              br numeric := round(coalesce((g->'broken'->>r.raw::text)::numeric,0)); ws numeric := round(coalesce((g->'waste'->>r.raw::text)::numeric,0));
              tot numeric; df numeric; rs text := nullif(trim(g->'reason'->>r.raw::text),'');
      begin
        tot := gd + nr + br + ws; df := tot - round(r.given);
        if tot = 0 then raise exception 'Enter the returned qty for %', r.name; end if;
        if df <> 0 and rs is null then v_need := v_need || r.name || ', '; end if;
        if gd > 0 then insert into public.wh_lines (batch_id, slip, line_type, item_id, qty, egg_pcs) values (b.id,'R1','GOOD',r.raw,gd,gd); end if;
        if nr > 0 then insert into public.wh_lines (batch_id, slip, line_type, item_id, qty, egg_pcs) values (b.id,'R1','NEAR EXPIRY',r.raw,nr,nr); end if;
        if br > 0 then insert into public.wh_lines (batch_id, slip, line_type, item_id, qty, egg_pcs) values (b.id,'R1','BROKEN',r.raw,br,br); end if;
        if ws > 0 then insert into public.wh_lines (batch_id, slip, line_type, item_id, qty, egg_pcs) values (b.id,'R1','WASTE',r.raw,ws,ws); end if;
        insert into public.wh_lines (batch_id, slip, line_type, item_id, qty, egg_pcs, calculated, difference, reason)
        values (b.id,'R1','CHECK',r.raw,tot,tot,round(r.given),df, case when df <> 0 then rs end);
        t_fgegg := t_fgegg + gd; t_near := t_near + nr; t_br := t_br + br; t_ws := t_ws + ws; t_ed := t_ed + df;
      end;
    end loop;
    -- packing material from unwrapped packs: reusable vs waste
    for r in
      select bom.item_id mat, round(sum(l.qty * bom.per_pack)) unw
        from public.wh_lines l join public.v_fg_bom bom on bom.fg_item_id = l.item_id and bom.item_type = 'MATERIAL'
       where l.batch_id = b.id and l.line_type = 'ISSUE FG' group by bom.item_id
    loop
      declare re numeric := least(round(coalesce((g->'reuse'->>r.mat::text)::numeric,0)), r.unw);
      begin
        if re > 0 then insert into public.wh_lines (batch_id, slip, line_type, item_id, qty, calculated) values (b.id,'R1','MATERIAL REUSABLE',r.mat,re,r.unw); end if;
        if r.unw - re > 0 then insert into public.wh_lines (batch_id, slip, line_type, item_id, qty, calculated) values (b.id,'R1','MATERIAL WASTE',r.mat,r.unw - re,r.unw); end if;
      end;
    end loop;
  end if;

  if v_need <> '' then raise exception 'Reason needed for the difference: %', rtrim(v_need, ', '); end if;

  v_sc  := greatest(coalesce(array_length(b.staff_ids,1),1),1);
  v_hrs := greatest(extract(epoch from now() - b.issued_at) / 3600, 0);
  v_end := ((b.work_date + case when b.shift = 'NIGHT' then 1 else 0 end)::timestamp
            + case when b.shift = 'NIGHT' then interval '5 hours' else interval '17 hours' end) at time zone 'Asia/Dubai';
  update public.wh_batches set status = 'CLOSED', returned_at = now(), received_by = p_duty,
         fg_packs = case when process = 'PRODUCTION' then t_fg end, good_egg_pcs = t_fgegg, near_pcs = t_near,
         broken_pcs = t_br, waste_pcs = t_ws, balance_egg_pcs = case when process = 'PRODUCTION' then t_bal end,
         egg_diff = t_ed, mat_diff = case when process = 'PRODUCTION' then t_md end,
         hours = round(v_hrs, 2), beyond_hours = round(greatest(extract(epoch from now() - v_end) / 3600, 0), 2),
         output_per_staff_hour = round(case when process = 'PRODUCTION' then t_fg else t_fgegg + t_near + t_br + t_ws end / (v_sc * greatest(v_hrs, 0.01)), 1)
   where id = b.id;
  return jsonb_build_object('batch_no', b.batch_no, 'egg_diff', t_ed, 'mat_diff', t_md);
end $$;

-- CANCEL a whole batch (within 24 hours of issue), reason required
create or replace function public.wh_cancel(p_batch bigint, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare b public.wh_batches;
begin
  if coalesce(trim(p_reason),'') = '' then raise exception 'Reason is required'; end if;
  select * into b from public.wh_batches where id = p_batch for update;
  if not found then raise exception 'Batch not found'; end if;
  perform public.require_role(array['ADMIN','ACCOUNTANT','RECEIVER'], b.branch_id);
  if b.status = 'CANCELLED' then raise exception 'Already cancelled'; end if;
  if now() - b.issued_at > interval '24 hours' and public.my_role() <> 'ADMIN' then
    raise exception 'Only admin can cancel a batch older than 24 hours'; end if;
  perform set_config('app.reason', p_reason, true);
  update public.wh_batches set status = 'CANCELLED', cancel_reason = p_reason where id = b.id;
end $$;

revoke execute on function public.wh_check_duty, public.wh_issue, public.wh_return, public.wh_cancel from public, anon;
grant execute on function public.wh_issue, public.wh_return, public.wh_cancel to authenticated;
commit;
