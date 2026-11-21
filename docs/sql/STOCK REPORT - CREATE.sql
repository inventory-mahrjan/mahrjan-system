-- STOCK REPORT - CREATE.sql
-- Import of the iTrade "Stock Report as on <date>" (Itemcode, Item Name, Item No, QTY, Cost, Selling, StockValue).
-- Only the latest report per company is kept: a new import replaces the previous one for that company.
-- The Cost of every matched item becomes the item's cost (items.unit_cost), used for stock count values.
-- Undo with: STOCK REPORT - REVERT.sql (puts back the item costs from before this was installed)

-- item costs before the first import, for the revert script
create table if not exists public.stock_report_cost_backup as select id as item_id, unit_cost from public.items;
alter table public.stock_report_cost_backup enable row level security;

create table if not exists public.stock_reports (
  id bigserial primary key,
  branch_id bigint not null references public.branches(id),
  warehouse text not null,
  as_on date not null,
  file_name text,
  line_count int not null default 0,
  total_qty numeric(14,3) not null default 0,
  total_value numeric(14,2) not null default 0,
  imported_at timestamptz not null default now(),
  imported_by text
);
create table if not exists public.stock_report_lines (
  id bigserial primary key,
  report_id bigint not null references public.stock_reports(id) on delete cascade,
  item_id bigint references public.items(id),
  item_code text, item_no text, item_name text,
  qty numeric(14,3), cost numeric(12,4), selling numeric(12,4), stock_value numeric(14,2)
);
create index if not exists stock_report_lines_report_idx on public.stock_report_lines (report_id);

alter table public.stock_reports enable row level security;
alter table public.stock_report_lines enable row level security;
grant select on public.stock_reports, public.stock_report_lines to authenticated;
drop policy if exists read_office on public.stock_reports;
create policy read_office on public.stock_reports for select to authenticated
  using (public.can_view('sri') and public.can_branch(branch_id));
drop policy if exists read_office on public.stock_report_lines;
create policy read_office on public.stock_report_lines for select to authenticated
  using (exists (select 1 from public.stock_reports r where r.id = report_id));

-- menu entry + access (admin always; accountant view and import)
insert into public.role_modules (module, label, grp, has_edit, sort) values ('sri', 'Stock report import', 'Daily flow', true, 12)
  on conflict (module) do nothing;
insert into public.role_access (role, module, can_view, can_edit) values ('ADMIN', 'sri', true, true), ('ACCOUNTANT', 'sri', true, true)
  on conflict do nothing;

-- p_lines = [{"item_id":1,"item_code":"629..","item_no":"1001","item_name":"..","qty":2340,"cost":3.36,"selling":4,"stock_value":7853.68}, ...]
create or replace function public.stock_report_save(p_branch bigint, p_warehouse text, p_as_on date, p_file text, p_lines jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare rid bigint; n int; nc int;
begin
  perform public.require_role(array['M:sri'], p_branch);
  if p_as_on is null or coalesce(trim(p_warehouse), '') = '' then raise exception 'Report date and warehouse are needed.'; end if;
  if jsonb_array_length(coalesce(p_lines, '[]')) = 0 then raise exception 'The report has no lines.'; end if;
  delete from public.stock_reports where branch_id = p_branch;     -- keep only the latest report
  insert into public.stock_reports (branch_id, warehouse, as_on, file_name, imported_by)
    values (p_branch, trim(p_warehouse), p_as_on, p_file, (public.me()).name) returning id into rid;
  insert into public.stock_report_lines (report_id, item_id, item_code, item_no, item_name, qty, cost, selling, stock_value)
    select rid, nullif(x->>'item_id', '')::bigint, x->>'item_code', x->>'item_no', x->>'item_name',
           coalesce(nullif(x->>'qty', '')::numeric, 0), nullif(x->>'cost', '')::numeric, nullif(x->>'selling', '')::numeric,
           coalesce(nullif(x->>'stock_value', '')::numeric, 0)
    from jsonb_array_elements(p_lines) x;
  get diagnostics n = row_count;
  update public.stock_reports r set line_count = n,
    total_qty = (select coalesce(sum(qty), 0) from public.stock_report_lines where report_id = rid),
    total_value = (select coalesce(sum(stock_value), 0) from public.stock_report_lines where report_id = rid)
  where r.id = rid;
  update public.items i set unit_cost = l.cost, updated_at = now()
  from public.stock_report_lines l
  where l.report_id = rid and l.item_id = i.id and l.cost > 0 and i.unit_cost is distinct from l.cost;
  get diagnostics nc = row_count;
  return jsonb_build_object('id', rid, 'lines', n, 'costs_updated', nc);
end $$;

revoke all on function public.stock_report_save(bigint, text, date, text, jsonb) from public, anon;
grant execute on function public.stock_report_save(bigint, text, date, text, jsonb) to authenticated;
