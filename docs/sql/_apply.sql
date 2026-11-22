-- GRANTS CLEANUP 2 - CREATE.sql
-- Signed-out visitors could still call a few functions through the default PUBLIC grant (they were blocked
-- inside by the role check, but should not be reachable at all). Triggers keep working (they need no grant).
-- login_unit stays open: the app calls it at sign-in.
-- Undo with: GRANTS CLEANUP 2 - REVERT.sql
revoke execute on function public.office_save(bigint, date, text, jsonb, jsonb) from public, anon;
revoke execute on function public.sc_delete_batch(bigint) from public, anon;
revoke execute on function public.sales_lines_deleted() from public, anon;
revoke execute on function public.van_day_cartons() from public, anon;
revoke execute on function public.sales_deletes_apply() from public, anon;
revoke execute on function public.sc_purge_daily_trg() from public, anon;
grant execute on function public.office_save(bigint, date, text, jsonb, jsonb), public.sc_delete_batch(bigint) to authenticated;
select string_agg(p.proname, ',') as still_open_to_signed_out from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef and has_function_privilege('anon', p.oid, 'execute');
