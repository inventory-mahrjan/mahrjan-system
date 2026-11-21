-- BARCODE FROM STOCK REPORT - CREATE.sql
-- Sets the item master barcode (and iTrade code where it was the same as the old barcode) to the
-- Itemcode of the latest stock report, for items matched by name whose barcode differs.
-- Also links report item 1037 (name cut short in iTrade) to item 68.
-- Old values are kept in item_barcode_backup. Undo with: BARCODE FROM STOCK REPORT - REVERT.sql
create table if not exists public.item_barcode_backup (item_id bigint primary key, barcode text, itrade_code text, saved_at timestamptz default now());
alter table public.item_barcode_backup enable row level security;

update public.stock_report_lines set item_id = 68 where item_no = '1037' and item_id is null and item_code = '6299006355855';

with ch as (
  select distinct on (i.id) i.id, i.barcode old_bc, i.itrade_code old_it, l.item_code new_bc, l.cost
  from public.stock_report_lines l join public.items i on i.id = l.item_id
  where i.barcode is distinct from l.item_code
    and not exists (select 1 from public.items o where o.id <> i.id and (o.barcode = l.item_code or o.itrade_code = l.item_code))
), bk as (
  insert into public.item_barcode_backup (item_id, barcode, itrade_code)
  select id, old_bc, old_it from ch on conflict (item_id) do nothing returning item_id
)
update public.items i set barcode = ch.new_bc,
  itrade_code = case when i.itrade_code is null or i.itrade_code = ch.old_bc then ch.new_bc else i.itrade_code end,
  unit_cost = case when ch.cost > 0 then ch.cost else i.unit_cost end, updated_at = now()
from ch where ch.id = i.id;

select i.id, i.name, b.barcode as old_barcode, i.barcode as new_barcode, i.itrade_code, i.unit_cost
from public.item_barcode_backup b join public.items i on i.id = b.item_id order by i.id;
