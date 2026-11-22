-- GRANTS CLEANUP 2 - REVERT.sql
grant execute on function public.office_save(bigint, date, text, jsonb, jsonb), public.sc_delete_batch(bigint),
  public.sales_lines_deleted(), public.van_day_cartons(), public.sales_deletes_apply(), public.sc_purge_daily_trg() to public;
