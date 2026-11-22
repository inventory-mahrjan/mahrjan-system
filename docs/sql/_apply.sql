-- STOCK COUNT PURGE FIX - CREATE.sql
-- Creating a stock count batch failed with "DELETE requires a WHERE clause": the 15-day clean-up emptied its
-- work list with a bare DELETE, which Supabase blocks for portal logins. Now it says "where true".
-- Undo with: STOCK COUNT PURGE FIX - REVERT.sql
do $$ declare d text; begin
  d := pg_get_functiondef('public.sc_purge_daily(int)'::regprocedure);
  execute replace(d, 'delete from _sc_old;', 'delete from _sc_old where true;');
end $$;
select position('delete from _sc_old where true;' in pg_get_functiondef('public.sc_purge_daily(int)'::regprocedure)) > 0 as fixed;
