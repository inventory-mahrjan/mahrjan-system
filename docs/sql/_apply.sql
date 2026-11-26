-- WAREHOUSE ADD TO BATCH - CREATE
-- Extra raw egg / material (production) or extra packs (cleaning) can be added to a batch that is still open (no return yet).
-- The lines join the same batch (slip I1), so the return counts original + additional issue together.
-- wh_lines.issue_no: 1 = original issue, 2, 3 ... = additional issues (each prints its own ADDITIONAL ISSUE slip).
alter table public.wh_lines add column if not exists issue_no smallint not null default 1;

create or replace function public.wh_issue_add(p_batch bigint, p_duty bigint, p_lines jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.wh_batches; v_no smallint; v_eggs numeric;
begin
  select * into b from public.wh_batches where id = p_batch for update;
  if not found then raise exception 'Batch not found'; end if;
  perform public.wh_check_duty(p_duty, b.branch_id);
  if b.status <> 'ISSUED' then raise exception '% is already % — additional issue is allowed only before the return.', b.batch_no, lower(b.status); end if;

  drop table if exists t_l;
  create temp table t_l on commit drop as
  select (x->>'fg_item_id')::bigint fg, nullif(x->>'item_id','')::bigint it, round(coalesce((x->>'qty')::numeric,0)) qty,
         nullif(x->>'exp_date','')::date exp, nullif(trim(x->>'origin'),'') origin
    from jsonb_array_elements(coalesce(p_lines,'[]')) x where coalesce((x->>'qty')::numeric,0) > 0;
  if not exists (select 1 from t_l) then raise exception 'Enter at least one qty.'; end if;
  if exists (select 1 from t_l t left join public.items i on i.id = t.fg and i.item_type = 'FG' where i.id is null) then
    raise exception 'Not a finished good in the list'; end if;
  if b.process = 'PRODUCTION' and exists (select 1 from t_l t where not exists
       (select 1 from public.v_fg_bom m where m.fg_item_id = t.fg and m.item_id = t.it)) then
    raise exception 'A line is not in the bill of materials of its finished good'; end if;

  select coalesce(max(issue_no),1) + 1 into v_no from public.wh_lines where batch_id = b.id and slip = 'I1';
  if b.process = 'PRODUCTION' then
    insert into public.wh_lines (batch_id, slip, line_type, for_item_id, item_id, qty, egg_pcs, exp_date, origin, issue_no)
    select b.id, 'I1', case when i.item_type = 'RAW_EGG' then 'ISSUE RAW' else 'ISSUE MATERIAL' end, t.fg, t.it, t.qty,
           case when i.item_type = 'RAW_EGG' then t.qty else 0 end,
           case when i.item_type = 'RAW_EGG' then t.exp end, case when i.item_type = 'RAW_EGG' then t.origin end, v_no
      from t_l t join public.items i on i.id = t.it;
  else
    insert into public.wh_lines (batch_id, slip, line_type, for_item_id, item_id, qty, egg_pcs, issue_no)
    select b.id, 'I1', 'ISSUE FG', t.fg, t.fg, t.qty, t.qty * coalesce(f.pcs_per_pack,0), v_no
      from t_l t join public.items f on f.id = t.fg;
  end if;
  select coalesce(sum(egg_pcs),0) into v_eggs from public.wh_lines where batch_id = b.id and slip = 'I1';
  update public.wh_batches set issued_egg_pcs = v_eggs, updated_at = now(), updated_by = auth.uid() where id = b.id;
  return jsonb_build_object('batch_id', b.id, 'batch_no', b.batch_no, 'issue_no', v_no, 'issued_egg_pcs', v_eggs);
end $$;
revoke all on function public.wh_issue_add(bigint, bigint, jsonb) from public, anon;
grant execute on function public.wh_issue_add(bigint, bigint, jsonb) to authenticated;
notify pgrst, 'reload schema';
