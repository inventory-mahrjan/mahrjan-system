-- Undo RLS SPEED: put every access rule back exactly as saved.
do $$
declare r record; s text;
begin
  for r in select * from public.policy_backup_rls_speed loop
    s := format('alter policy %I on public.%I', r.polname, r.relname);
    if r.qual is not null then s := s || ' using (' || r.qual || ')'; end if;
    if r.wcheck is not null then s := s || ' with check (' || r.wcheck || ')'; end if;
    execute s;
  end loop;
end $$;
drop table public.policy_backup_rls_speed;
notify pgrst, 'reload schema';
