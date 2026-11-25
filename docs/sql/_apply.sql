-- GRANTS CLEANUP 3: remove table rights the portal / app never use.
-- New tables were getting TRUNCATE / TRIGGER / REFERENCES for anon and authenticated (Supabase default).
-- Safety-copy tables (*_backup) get no access at all from logins. Future tables no longer get anon rights.
do $$ declare r record; begin
  for r in select relname from pg_class where relnamespace='public'::regnamespace and relkind in ('r','p') loop
    execute format('revoke truncate, trigger, references on public.%I from anon, authenticated', r.relname);
    if r.relname like '%\_backup%' then
      execute format('revoke all on public.%I from anon, authenticated', r.relname);
    end if;
  end loop;
end $$;
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke truncate, trigger, references on tables from authenticated;
