-- GRANTS CLEANUP - REVERT.sql
-- Puts back the rights removed by GRANTS CLEANUP - CREATE.sql.
do $$ declare t text; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' loop
    execute format('grant truncate, trigger, references on public.%I to anon, authenticated', t);
  end loop;
end $$;
grant execute on function public.office_save to anon;
grant execute on function public.sc_delete_batch to anon;
