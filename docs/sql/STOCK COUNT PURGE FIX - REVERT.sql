-- STOCK COUNT PURGE FIX - REVERT.sql
do $$ declare d text; begin
  d := pg_get_functiondef('public.sc_purge_daily(int)'::regprocedure);
  execute replace(d, 'delete from _sc_old where true;', 'delete from _sc_old;');
end $$;
