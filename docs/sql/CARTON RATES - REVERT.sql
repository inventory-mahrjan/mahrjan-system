-- CARTON RATES - REVERT  (back to fixed 0.50 / 0.25)
create or replace function public.van_day_cartons() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT') or new.carton_small is distinct from old.carton_small or new.carton_big is distinct from old.carton_big then
    delete from public.expenses where van_day_id = new.id and expense_type in ('CARTON SMALL','CARTON BIG');
    if coalesce(new.carton_small,0) > 0 then insert into public.expenses (van_day_id, expense_type, amount, note)
      values (new.id, 'CARTON SMALL', round(new.carton_small * 0.50, 2), new.carton_small || ' @ 0.50'); end if;
    if coalesce(new.carton_big,0) > 0 then insert into public.expenses (van_day_id, expense_type, amount, note)
      values (new.id, 'CARTON BIG', round(new.carton_big * 0.25, 2), new.carton_big || ' @ 0.25'); end if;
  end if;
  return new;
end $$;
drop table if exists public.app_settings;
select 'carton rates fixed again' as result;
