-- MAHRJAN SYSTEM - APP BRIDGE (REVERT)
begin;
drop trigger if exists trg_van_day_cartons on public.van_day;
drop function if exists public.van_day_cartons();
drop trigger if exists trg_sales_lines_deleted on public.sales_lines;
drop function if exists public.sales_lines_deleted();
update public.sales_lines set cancelled = false, cancel_reason = null where cancel_reason = 'DELETE LIST';
drop function if exists public.app_delete(bigint, date, text, text, boolean);
drop function if exists public.is_deleted_invoice(bigint, text, text);
drop function if exists public.inv_key(text);
drop table if exists public.sales_deletes;
drop function if exists public.app_summary(bigint, jsonb);
drop function if exists public.app_day(bigint, date);
drop function if exists public.app_collections(bigint, jsonb, boolean);
drop function if exists public.app_van(bigint, text);
drop function if exists public.login_unit(text);
alter table public.van_day drop column if exists summary;
do $$ declare d text; begin
  d := pg_get_functiondef('public.save_expenses'::regproc);
  d := replace(d, ' and expense_type not in (''CARTON SMALL'',''CARTON BIG'');', ';'); execute d;
end $$;
commit;
