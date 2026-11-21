-- GRANTS CLEANUP - CREATE.sql
-- Removes table rights the app never uses (TRUNCATE skips access rules) and stops
-- not-signed-in callers from reaching two write functions (they already refuse, this is belt and braces).
-- Undo with: GRANTS CLEANUP - REVERT.sql
do $$ declare t text; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' loop
    execute format('revoke truncate, trigger, references on public.%I from anon, authenticated', t);
  end loop;
end $$;
revoke execute on function public.office_save from anon;
revoke execute on function public.sc_delete_batch from anon;
