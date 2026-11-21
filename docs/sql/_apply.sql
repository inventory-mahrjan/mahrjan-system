-- STOCK COUNT COUNTRIES - CREATE
-- Country of origin comes from a list the admin keeps (portal → Items & BOM → Countries); the app shows only these.
create table if not exists public.sc_countries (
  name       text primary key check (name = upper(trim(name)) and name <> ''),
  active     boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now()
);
alter table public.sc_countries enable row level security;
grant select, insert, update, delete on public.sc_countries to authenticated;
drop policy if exists read_all on public.sc_countries;
create policy read_all on public.sc_countries for select to authenticated using (true);
drop policy if exists admin_write on public.sc_countries;
create policy admin_write on public.sc_countries for all to authenticated using (public.my_role() = 'ADMIN') with check (public.my_role() = 'ADMIN');
insert into public.sc_countries (name, sort_order) values ('UAE',1),('SAUDI ARABIA',2),('OMAN',3),('PAKISTAN',4),('TURKEY',5),('INDIA',6),('JORDAN',7)
  on conflict (name) do nothing;

-- the app's download takes the countries from this list only
do $$ declare d text; a text; b text; begin
  d := pg_get_functiondef('public.sc_download(bigint)'::regprocedure);
  a := substring(d from '''countries'', \(select .*?''BRAZIL''\]\) x\) t\)');
  if a is null then raise exception 'sc_download text not as expected - nothing changed'; end if;
  b := '''countries'', (select coalesce(jsonb_agg(name order by sort_order, name), ''[]'') from public.sc_countries where active)';
  execute replace(d, a, b);
end $$;
select 'countries list ready' as result;
