-- BOARD AFTER RETURN - REVERT (board only while OPEN / LOADED, as before)
create or replace function public.post_loading(p_salesman bigint, p_date date, p_van bigint, p_start_km integer, p_load_temp numeric, p_lines jsonb)
returns bigint language plpgsql security definer set search_path to 'public' as $function$
declare s public.staff; d public.van_day; v_route bigint;
begin
  select * into s from public.staff where id = p_salesman and role = 'SALESMAN' and active;
  if not found then raise exception 'Salesman % not found or inactive', p_salesman; end if;
  perform public.require_role(array['M:load'], s.branch_id);
  if jsonb_array_length(coalesce(p_lines,'[]')) = 0 then raise exception 'No loading lines'; end if;
  select route_id into v_route from public.customer_assignment where salesman_id = p_salesman and to_date is null and route_id is not null group by route_id order by count(*) desc limit 1;
  insert into public.van_day (branch_id, business_date, salesman_id, route_id, van_id, start_km, load_temp, load_time, status)
    values (s.branch_id, p_date, p_salesman, v_route, p_van, p_start_km, p_load_temp, localtime, 'LOADED')
    on conflict (salesman_id, business_date) do nothing;
  select * into d from public.van_day where salesman_id = p_salesman and business_date = p_date;
  d := public.day_for_update(d.id, array['M:load'], array['OPEN','LOADED']);
  update public.van_day set van_id = coalesce(p_van, van_id), start_km = coalesce(p_start_km, start_km), load_temp = coalesce(p_load_temp, load_temp), status = 'LOADED' where id = d.id;
  delete from public.loading_lines where van_day_id = d.id;
  insert into public.loading_lines (van_day_id, item_id, qty)
    select d.id, (x->>'item_id')::bigint, sum((x->>'qty')::numeric) from jsonb_array_elements(p_lines) x
    where coalesce((x->>'qty')::numeric, 0) > 0 group by (x->>'item_id')::bigint;
  return d.id;
end $function$;
notify pgrst, 'reload schema';
