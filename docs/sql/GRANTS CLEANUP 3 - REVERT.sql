-- Undo GRANTS CLEANUP 3 (puts back the Supabase default rights)
do $$ declare r record; begin
  for r in select relname from pg_class where relnamespace='public'::regnamespace and relkind in ('r','p') loop
    execute format('grant truncate, trigger, references on public.%I to anon, authenticated', r.relname);
  end loop;
end $$;
alter default privileges for role postgres in schema public grant all on tables to anon;
alter default privileges for role postgres in schema public grant truncate, trigger, references on tables to authenticated;
