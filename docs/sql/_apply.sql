-- CARTON RATES - CREATE
-- Carton rates (AED per empty carton returned) kept in a settings table the admin changes in the portal
-- (Admin → Settings). Before: fixed in the database at small 0.50 / big 0.25.
-- A new rate applies to returns saved from then on; days already saved keep their amount.
create table if not exists public.app_settings (
  key        text primary key,
  value      numeric not null,
  label      text,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);
alter table public.app_settings enable row level security;
grant select, insert, update on public.app_settings to authenticated;
drop policy if exists read_all on public.app_settings;
create policy read_all on public.app_settings for select to authenticated using (true);
drop policy if exists admin_write on public.app_settings;
create policy admin_write on public.app_settings for all to authenticated using (public.my_role() = 'ADMIN') with check (public.my_role() = 'ADMIN');
insert into public.app_settings (key, value, label) values ('CARTON_SMALL', 0.50, 'Carton small rate (AED each)'), ('CARTON_BIG', 0.25, 'Carton big rate (AED each)')
  on conflict (key) do nothing;

create or replace function public.van_day_cartons() returns trigger language plpgsql security definer set search_path = public as $$
declare rs numeric := coalesce((select value from public.app_settings where key = 'CARTON_SMALL'), 0.50);
        rb numeric := coalesce((select value from public.app_settings where key = 'CARTON_BIG'), 0.25);
begin
  if (tg_op = 'INSERT') or new.carton_small is distinct from old.carton_small or new.carton_big is distinct from old.carton_big then
    delete from public.expenses where van_day_id = new.id and expense_type in ('CARTON SMALL','CARTON BIG');
    if coalesce(new.carton_small,0) > 0 then insert into public.expenses (van_day_id, expense_type, amount, note)
      values (new.id, 'CARTON SMALL', round(new.carton_small * rs, 2), new.carton_small || ' @ ' || to_char(rs, 'FM990.00')); end if;
    if coalesce(new.carton_big,0) > 0 then insert into public.expenses (van_day_id, expense_type, amount, note)
      values (new.id, 'CARTON BIG', round(new.carton_big * rb, 2), new.carton_big || ' @ ' || to_char(rb, 'FM990.00')); end if;
  end if;
  return new;
end $$;
select 'carton rates ready' as result;
