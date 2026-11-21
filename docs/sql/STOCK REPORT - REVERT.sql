-- STOCK REPORT - REVERT.sql
-- Undoes STOCK REPORT - CREATE.sql: puts back every item's cost from before it was installed,
-- then removes the stock report tables, function and menu entry.

update public.items i set unit_cost = b.unit_cost from public.stock_report_cost_backup b
where b.item_id = i.id and i.unit_cost is distinct from b.unit_cost;

drop function if exists public.stock_report_save(bigint, text, date, text, jsonb);
drop table if exists public.stock_report_lines;
drop table if exists public.stock_reports;
delete from public.role_access where module = 'sri';
delete from public.role_modules where module = 'sri';
drop table if exists public.stock_report_cost_backup;
