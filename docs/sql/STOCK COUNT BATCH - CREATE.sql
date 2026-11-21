-- =====================================================================
-- STOCK COUNT BATCH - CREATE
-- New stock count (batches):
--   * Admin / accountant creates a BATCH in the portal: company, date, Daily/Weekly, counted by,
--     categories to count (Raw egg, Finished goods, Plain tray, Labelled tray, Label roll).
--   * The receiver downloads the batch in the app, counts offline (shelf, scan, qty, expiry, country),
--     saves on the device and POSTS when online. Admin can edit after posting.
--   * Recount batches for big differences, cut-off time, damage stock type, iTrade stock per batch.
-- New item fields: material_kind (TRAY / LABEL / CARTON / OTHER), pcs_per_box (box of trays, roll of
-- labels), unit_cost (AED, for the value of differences).
-- The old simple stock count tables are not touched.
-- Revert: STOCK COUNT BATCH - REVERT.sql
-- =====================================================================
alter table public.items add column if not exists material_kind text check (material_kind in ('TRAY','LABEL','CARTON','OTHER'));
alter table public.items add column if not exists pcs_per_box integer;
alter table public.items add column if not exists unit_cost numeric(12,4);
update public.items set material_kind = case when name ilike '%label%' or name ilike '%sticker%' then 'LABEL'
                                             when name ilike '%tray%' then 'TRAY'
                                             when name ilike '%carton%' or name ilike '%box%' then 'CARTON' else 'OTHER' end
 where item_type = 'MATERIAL' and material_kind is null;

create table if not exists public.sc_batches (
  id             bigint generated always as identity primary key,
  batch_no       text unique,
  branch_id      bigint not null references public.branches(id),
  count_date     date not null,
  count_type     text not null check (count_type in ('DAILY','WEEKLY')),
  counted_by     bigint references public.staff(id),
  categories     text[] not null check (categories <@ array['RAW','FG','TRAY','LTRAY','LABEL']::text[] and cardinality(categories) > 0),
  status         text not null default 'OPEN' check (status in ('OPEN','DOWNLOADED','POSTED','CANCELLED')),
  parent_id      bigint references public.sc_batches(id),          -- recount of this batch
  recount_items  bigint[],                                         -- recount: only these items
  note           text,
  cutoff_at      timestamptz,                                      -- counting started (first download)
  created_by     uuid default auth.uid(),
  created_at     timestamptz not null default now(),
  downloaded_at  timestamptz,
  downloaded_by  uuid,
  posted_at      timestamptz,
  posted_by      uuid,
  edited_at      timestamptz,
  edited_by      uuid
);
create index if not exists sc_batches_branch_idx on public.sc_batches (branch_id, count_date);

create table if not exists public.sc_lines (
  id              bigint generated always as identity primary key,
  batch_id        bigint not null references public.sc_batches(id) on delete cascade,
  entry_no        integer not null,
  shelf           text,
  category        text not null check (category in ('RAW','FG','TRAY','LTRAY','LABEL')),
  stock_type      text check (stock_type in ('FRESH','GRV','CLEANED','DAMAGE')),
  scanned_barcode text,
  item_id         bigint not null references public.items(id),
  qty_big         numeric(12,2) not null default 0 check (qty_big >= 0),     -- ctn / box / roll
  qty_tray        numeric(12,2) not null default 0 check (qty_tray >= 0),    -- raw egg trays
  qty_small       numeric(12,2) not null default 0 check (qty_small >= 0),   -- pcs / pkts
  total_qty       numeric(14,2) not null default 0 check (total_qty >= 0),
  unit            text not null check (unit in ('PCS','PACKS')),
  exp_date        date,
  country         text,
  pair_key        text,                                                      -- labelled tray: tray + label share it
  zero_confirmed  boolean not null default false,
  scanned_at      timestamptz,
  device_saved_at timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists sc_lines_batch_idx on public.sc_lines (batch_id);

-- iTrade / system stock for a batch (uploaded in the portal) — the receiver never sees it (blind count)
create table if not exists public.sc_system (
  batch_id  bigint not null references public.sc_batches(id) on delete cascade,
  item_id   bigint not null references public.items(id),
  qty       numeric(14,2) not null,
  primary key (batch_id, item_id)
);

alter table public.sc_batches enable row level security;
alter table public.sc_lines   enable row level security;
alter table public.sc_system  enable row level security;
grant select on public.sc_batches, public.sc_lines, public.sc_system to authenticated;
drop policy if exists read_branch on public.sc_batches;
create policy read_branch on public.sc_batches for select to authenticated
  using (public.can_branch(branch_id) and public.my_role() in ('ADMIN','ACCOUNTANT','RECEIVER','VIEWER'));
drop policy if exists read_by_batch on public.sc_lines;
create policy read_by_batch on public.sc_lines for select to authenticated
  using (exists (select 1 from public.sc_batches b where b.id = batch_id));
drop policy if exists read_office on public.sc_system;
create policy read_office on public.sc_system for select to authenticated
  using (public.my_role() in ('ADMIN','ACCOUNTANT','VIEWER') and exists (select 1 from public.sc_batches b where b.id = batch_id));

-- ---------------------------------------------------------------------
-- create (or change, while not posted) a batch — ADMIN / ACCOUNTANT
create or replace function public.sc_save_batch(p_id bigint, p_branch bigint, p_date date, p_type text, p_counted_by bigint,
  p_categories text[], p_note text default null, p_parent bigint default null, p_items bigint[] default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.sc_batches; v_code text; n integer;
begin
  perform public.require_role(array['ADMIN','ACCOUNTANT'], p_branch);
  if p_date is null then raise exception 'Choose the count date.'; end if;
  if p_categories is null or cardinality(p_categories) = 0 then raise exception 'Tick at least one category.'; end if;
  if p_id is null then
    insert into public.sc_batches (branch_id, count_date, count_type, counted_by, categories, note, parent_id, recount_items)
    values (p_branch, p_date, upper(p_type), p_counted_by, p_categories, nullif(trim(coalesce(p_note,'')),''), p_parent, p_items)
    returning * into b;
    select code into v_code from public.branches where id = p_branch;
    select count(*) into n from public.sc_batches where branch_id = p_branch and count_date = p_date and id <= b.id;
    update public.sc_batches set batch_no = 'SC-' || case v_code when 'MGT' then 'AJ' else 'AQ' end || '-' || to_char(p_date,'YYYYMMDD') || '-' || lpad(n::text, 2, '0') || case when p_parent is not null then '-R' else '' end
     where id = b.id returning * into b;
  else
    select * into b from public.sc_batches where id = p_id for update;
    if b.id is null then raise exception 'Batch not found.'; end if;
    if b.status = 'POSTED' then raise exception 'This batch is posted; edit the counted lines instead.'; end if;
    update public.sc_batches set branch_id = p_branch, count_date = p_date, count_type = upper(p_type), counted_by = p_counted_by,
           categories = p_categories, note = nullif(trim(coalesce(p_note,'')),''), edited_at = now(), edited_by = auth.uid()
     where id = p_id returning * into b;
  end if;
  return to_jsonb(b);
end $$;

-- cancel an unposted batch
create or replace function public.sc_cancel_batch(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare b public.sc_batches;
begin
  select * into b from public.sc_batches where id = p_id;
  if b.id is null then raise exception 'Batch not found.'; end if;
  perform public.require_role(array['ADMIN','ACCOUNTANT'], b.branch_id);
  if b.status = 'POSTED' then raise exception 'A posted batch cannot be cancelled.'; end if;
  update public.sc_batches set status = 'CANCELLED', edited_at = now(), edited_by = auth.uid() where id = p_id;
end $$;

-- the app downloads a batch: everything needed to count offline (no system stock — blind count)
create or replace function public.sc_download(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.sc_batches; v jsonb;
begin
  select * into b from public.sc_batches where id = p_id;
  if b.id is null then raise exception 'Batch not found.'; end if;
  perform public.require_role(array['ADMIN','ACCOUNTANT','RECEIVER'], b.branch_id);
  if b.status in ('POSTED','CANCELLED') then raise exception 'This batch is %.', lower(b.status); end if;
  update public.sc_batches set status = 'DOWNLOADED', downloaded_at = coalesce(downloaded_at, now()), downloaded_by = coalesce(downloaded_by, auth.uid()),
         cutoff_at = coalesce(cutoff_at, now()) where id = p_id returning * into b;
  select jsonb_build_object(
    'batch', jsonb_build_object('id', b.id, 'no', b.batch_no, 'date', b.count_date, 'type', b.count_type, 'categories', b.categories,
             'branch', (select name from public.branches where id = b.branch_id), 'counted_by', (select name from public.staff where id = b.counted_by),
             'recount_items', b.recount_items, 'cutoff_at', b.cutoff_at),
    'items', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'bc', i.barcode, 'code', i.itrade_code, 'n', i.name, 's', i.short_name, 't', i.item_type,
                     'k', i.material_kind, 'ppp', i.pcs_per_pack, 'ppc', i.packs_per_carton, 'pcc', i.pcs_per_carton, 'ppt', i.pcs_per_tray, 'ppb', i.pcs_per_box, 'o', i.display_order)
                     order by i.display_order nulls last, i.name), '[]') from public.items i where i.active),
    'bom', (select coalesce(jsonb_agg(jsonb_build_object('fg', r.fg_item_id, 'm', r.raw_item_id)), '[]')
              from public.item_recipe r join public.items m on m.id = r.raw_item_id where r.active and m.item_type = 'MATERIAL' and m.material_kind in ('TRAY','LABEL')),
    'countries', (select coalesce(jsonb_agg(c order by c), '[]') from (select distinct upper(trim(country)) c from public.sc_lines where coalesce(trim(country),'') <> ''
                    union select x from unnest(array['UAE','OMAN','SAUDI ARABIA','INDIA','TURKEY','UKRAINE','PAKISTAN','IRAN','BRAZIL']) x) t),
    'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.entry_no), '[]') from public.sc_lines l where l.batch_id = b.id)
  ) into v;
  return v;
end $$;

-- the app saves its lines (the whole set kept on the device) and posts at the end
-- p_lines: [{entry_no, shelf, category, stock_type, scanned_barcode, item_id, qty_big, qty_tray, qty_small, total_qty, unit, exp_date, country, pair_key, zero_confirmed, scanned_at}]
create or replace function public.sc_upload(p_id bigint, p_lines jsonb, p_post boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.sc_batches; n integer;
begin
  select * into b from public.sc_batches where id = p_id for update;
  if b.id is null then raise exception 'Batch not found.'; end if;
  if public.my_role() in ('ADMIN','ACCOUNTANT') then perform public.require_role(array['ADMIN','ACCOUNTANT'], b.branch_id);
  else perform public.require_role(array['RECEIVER'], b.branch_id);
       if b.status in ('POSTED','CANCELLED') then raise exception 'This batch is already %. Ask the office to change it.', lower(b.status); end if; end if;
  if b.status = 'CANCELLED' then raise exception 'This batch is cancelled.'; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p_lines,'[]')) x where not ((x->>'category') = any(b.categories)))
    then raise exception 'A line is in a category that is not part of this batch.'; end if;
  delete from public.sc_lines where batch_id = p_id;
  insert into public.sc_lines (batch_id, entry_no, shelf, category, stock_type, scanned_barcode, item_id, qty_big, qty_tray, qty_small,
                               total_qty, unit, exp_date, country, pair_key, zero_confirmed, scanned_at, device_saved_at)
  select p_id, coalesce((x->>'entry_no')::int, ord::int), nullif(upper(trim(x->>'shelf')),''), x->>'category', nullif(x->>'stock_type',''), nullif(x->>'scanned_barcode',''),
         (x->>'item_id')::bigint, coalesce(nullif(x->>'qty_big','')::numeric,0), coalesce(nullif(x->>'qty_tray','')::numeric,0), coalesce(nullif(x->>'qty_small','')::numeric,0),
         coalesce(nullif(x->>'total_qty','')::numeric,0), coalesce(nullif(x->>'unit',''),'PCS'), nullif(x->>'exp_date','')::date, nullif(upper(trim(x->>'country')),''),
         nullif(x->>'pair_key',''), coalesce((x->>'zero_confirmed')::boolean,false), nullif(x->>'scanned_at','')::timestamptz, now()
    from jsonb_array_elements(coalesce(p_lines,'[]')) with ordinality t(x, ord);
  get diagnostics n = row_count;
  if p_post and b.status <> 'POSTED' then
    update public.sc_batches set status = 'POSTED', posted_at = now(), posted_by = auth.uid(), cutoff_at = coalesce(cutoff_at, now()) where id = p_id;
  elsif b.status = 'POSTED' then
    update public.sc_batches set edited_at = now(), edited_by = auth.uid() where id = p_id;
  elsif b.status = 'OPEN' then
    update public.sc_batches set status = 'DOWNLOADED', downloaded_at = coalesce(downloaded_at, now()), cutoff_at = coalesce(cutoff_at, now()) where id = p_id;
  end if;
  return jsonb_build_object('lines', n, 'posted', p_post or b.status = 'POSTED');
end $$;

-- iTrade / system stock for a batch: p_rows = [{"item_id":1,"qty":120}] — ADMIN / ACCOUNTANT
create or replace function public.sc_set_system(p_id bigint, p_rows jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare b public.sc_batches; n integer;
begin
  select * into b from public.sc_batches where id = p_id;
  if b.id is null then raise exception 'Batch not found.'; end if;
  perform public.require_role(array['ADMIN','ACCOUNTANT'], b.branch_id);
  delete from public.sc_system where batch_id = p_id;
  insert into public.sc_system (batch_id, item_id, qty)
  select p_id, (x->>'item_id')::bigint, sum((x->>'qty')::numeric) from jsonb_array_elements(p_rows) x
   where (x->>'item_id') is not null group by (x->>'item_id')::bigint;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.sc_save_batch(bigint, bigint, date, text, bigint, text[], text, bigint, bigint[]) from public, anon;
revoke all on function public.sc_cancel_batch(bigint) from public, anon;
revoke all on function public.sc_download(bigint) from public, anon;
revoke all on function public.sc_upload(bigint, jsonb, boolean) from public, anon;
revoke all on function public.sc_set_system(bigint, jsonb) from public, anon;
grant execute on function public.sc_save_batch(bigint, bigint, date, text, bigint, text[], text, bigint, bigint[]) to authenticated;
grant execute on function public.sc_cancel_batch(bigint) to authenticated;
grant execute on function public.sc_download(bigint) to authenticated;
grant execute on function public.sc_upload(bigint, jsonb, boolean) to authenticated;
grant execute on function public.sc_set_system(bigint, jsonb) to authenticated;
