-- RLS SPEED: access rules call my_role() / my_branch() / my_staff_id() once per query
-- instead of once per row (same rules, written as (select ...)). Big reads (sales_lines etc.) ~200x faster.
-- Originals saved in public.policy_backup_rls_speed; undo with "RLS SPEED - REVERT.sql".
create table if not exists public.policy_backup_rls_speed(
  relname text, polname text, qual text, wcheck text, saved_at timestamptz default now(),
  primary key(relname, polname));
revoke all on public.policy_backup_rls_speed from anon, authenticated;

create or replace function public._rls_fast(e text) returns text language plpgsql immutable as $f$
declare out text := ''; i int; j int; d int; arg text;
begin
  if e is null then return null; end if;
  -- can_branch(ARG)  ->  inline with one-time lookups
  loop
    i := strpos(e, 'can_branch(');
    exit when i = 0;
    j := i + length('can_branch('); d := 1;
    while d > 0 loop
      if substr(e, j, 1) = '(' then d := d + 1; elsif substr(e, j, 1) = ')' then d := d - 1; end if;
      j := j + 1;
    end loop;
    arg := substr(e, i + length('can_branch('), j - 1 - (i + length('can_branch(')));
    out := out || substr(e, 1, i - 1) ||
      '((select public.my_role()) is not null and ((select public.my_branch()) is null or (select public.my_branch()) = (' || arg || ')::bigint))';
    e := substr(e, j);
  end loop;
  e := out || e;
  e := regexp_replace(e, '(?<![.\w])(my_role|my_staff_id|my_branch)\(\)', '(select public.\1())', 'g');
  return e;
end $f$;

do $$
declare r record; q text; w text; s text;
begin
  for r in
    select c.relname, p.polname, pg_get_expr(p.polqual, p.polrelid) qual, pg_get_expr(p.polwithcheck, p.polrelid) wc
    from pg_policy p join pg_class c on c.oid = p.polrelid
    where c.relnamespace = 'public'::regnamespace
      and (coalesce(pg_get_expr(p.polqual, p.polrelid), '') || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''))
          ~ '(^|[^.\w])(can_branch|my_role|my_staff_id|my_branch)\('
  loop
    insert into public.policy_backup_rls_speed(relname, polname, qual, wcheck)
      values (r.relname, r.polname, r.qual, r.wc) on conflict do nothing;
    q := public._rls_fast(r.qual); w := public._rls_fast(r.wc);
    s := format('alter policy %I on public.%I', r.polname, r.relname);
    if q is not null then s := s || ' using (' || q || ')'; end if;
    if w is not null then s := s || ' with check (' || w || ')'; end if;
    execute s;
  end loop;
end $$;
drop function public._rls_fast(text);
notify pgrst, 'reload schema';
