-- OFFICE ENTRY - CREATE
-- Office corrections (admin / accountant) of a salesman's loading, return, expenses and collections for a date,
-- also after the van has returned or been settled (a settled day goes back to RETURNED so cash is settled again).
-- A closed day must be reopened first in Van days. Every save is kept in office_log (before / after).
create table if not exists public.office_log (
  id          bigserial primary key,
  van_day_id  bigint references public.van_day(id) on delete cascade,
  module      text not null,
  before_data jsonb,
  after_data  jsonb,
  edited_by   uuid default auth.uid(),
  edited_at   timestamptz not null default now()
);
alter table public.office_log enable row level security;
drop policy if exists office_log_read on public.office_log;
create policy office_log_read on public.office_log for select to authenticated
  using (public.my_role() in ('ADMIN','ACCOUNTANT'));

create or replace function public.office_save(p_salesman bigint, p_date date, p_module text, p_head jsonb, p_lines jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare s public.staff; d public.van_day; m text := upper(coalesce(p_module,'')); v_before jsonb; v_after jsonb; v_route bigint;
begin
  select * into s from public.staff where id = p_salesman and role = 'SALESMAN';
  if not found then raise exception 'Salesman not found.'; end if;
  perform public.require_role(array['ACCOUNTANT','ADMIN'], s.branch_id);
  p_head := coalesce(p_head, '{}'::jsonb); p_lines := coalesce(p_lines, '[]'::jsonb);

  select * into d from public.van_day where salesman_id = p_salesman and business_date = p_date for update;
  if d.id is null then
    if m <> 'LOADING' then raise exception 'No loading for this salesman on this date. Enter the loading first.'; end if;
    select route_id into v_route from public.customer_assignment where salesman_id = p_salesman and to_date is null and route_id is not null
     group by route_id order by count(*) desc limit 1;
    insert into public.van_day (branch_id, business_date, salesman_id, route_id, status) values (s.branch_id, p_date, p_salesman, v_route, 'LOADED') returning * into d;
  end if;
  if d.status = 'CLOSED' then raise exception 'This van day is closed. Reopen it in Van days first.'; end if;

  if m = 'LOADING' then
    select jsonb_build_object('van_id', d.van_id, 'start_km', d.start_km, 'load_temp', d.load_temp, 'lines', coalesce(jsonb_agg(jsonb_build_object('item_id', item_id, 'qty', qty) order by item_id), '[]'))
      into v_before from public.loading_lines where van_day_id = d.id;
    update public.van_day set van_id = nullif(p_head->>'van_id','')::bigint, start_km = nullif(p_head->>'start_km','')::integer,
           load_temp = nullif(p_head->>'load_temp','')::numeric, load_time = coalesce(load_time, localtime),
           status = case when status = 'OPEN' then 'LOADED' else status end where id = d.id;
    delete from public.loading_lines where van_day_id = d.id;
    insert into public.loading_lines (van_day_id, item_id, qty)
    select d.id, (x->>'item_id')::bigint, sum((x->>'qty')::numeric) from jsonb_array_elements(p_lines) x
     where coalesce((x->>'qty')::numeric,0) > 0 group by (x->>'item_id')::bigint;
  elsif m = 'RETURN' then
    if p_head ? 'end_km' and nullif(p_head->>'end_km','') is not null and d.start_km is not null and (p_head->>'end_km')::integer < d.start_km then
      raise exception 'End KM % is less than start KM %', p_head->>'end_km', d.start_km; end if;
    select jsonb_build_object('end_km', d.end_km, 'unload_temp', d.unload_temp, 'carton_small', d.carton_small, 'carton_big', d.carton_big,
           'lines', coalesce(jsonb_agg(to_jsonb(r) - 'van_day_id' order by r.item_id), '[]')) into v_before from public.return_lines r where van_day_id = d.id;
    update public.van_day set end_km = nullif(p_head->>'end_km','')::integer, unload_temp = nullif(p_head->>'unload_temp','')::numeric,
           carton_small = coalesce(nullif(p_head->>'carton_small','')::integer, 0), carton_big = coalesce(nullif(p_head->>'carton_big','')::integer, 0),
           unload_time = coalesce(unload_time, localtime), status = case when status in ('OPEN','LOADED') then 'RETURNED' else status end where id = d.id;
    delete from public.return_lines where van_day_id = d.id;
    insert into public.return_lines (van_day_id, item_id, good, damage, expiry, waste, foc)
    select d.id, (x->>'item_id')::bigint, sum(coalesce((x->>'good')::numeric,0)), sum(coalesce((x->>'damage')::numeric,0)),
           sum(coalesce((x->>'expiry')::numeric,0)), sum(coalesce((x->>'waste')::numeric,0)), sum(coalesce((x->>'foc')::numeric,0))
      from jsonb_array_elements(p_lines) x group by (x->>'item_id')::bigint
    having sum(coalesce((x->>'good')::numeric,0) + coalesce((x->>'damage')::numeric,0) + coalesce((x->>'expiry')::numeric,0) + coalesce((x->>'waste')::numeric,0) + coalesce((x->>'foc')::numeric,0)) > 0;
  elsif m = 'EXPENSE' then
    select coalesce(jsonb_agg(to_jsonb(e) - 'van_day_id' order by e.id), '[]') into v_before from public.expenses e where van_day_id = d.id and expense_type not in ('CARTON SMALL','CARTON BIG');
    delete from public.expenses where van_day_id = d.id and expense_type not in ('CARTON SMALL','CARTON BIG');
    insert into public.expenses (van_day_id, expense_type, amount, customer_id, note)
    select d.id, x->>'expense_type', (x->>'amount')::numeric, nullif(x->>'customer_id','')::bigint, nullif(x->>'note','')
      from jsonb_array_elements(p_lines) x where coalesce((x->>'amount')::numeric,0) > 0 and x->>'expense_type' not in ('CARTON SMALL','CARTON BIG');
  elsif m = 'COLLECTION' then
    select coalesce(jsonb_agg(to_jsonb(c) - 'van_day_id' order by c.id), '[]') into v_before from public.collections c where van_day_id = d.id;
    delete from public.collections where van_day_id = d.id;
    insert into public.collections (van_day_id, receipt_no, invoice_no, customer_id, mode, amount)
    select d.id, x->>'receipt_no', nullif(x->>'invoice_no',''), (x->>'customer_id')::bigint, coalesce(nullif(x->>'mode',''),'CASH'), (x->>'amount')::numeric
      from jsonb_array_elements(p_lines) x where coalesce((x->>'amount')::numeric,0) > 0;
  else
    raise exception 'Unknown module %', p_module;
  end if;

  -- a settled day goes back to RETURNED: its cash must be settled again
  update public.van_day set status = 'RETURNED' where id = d.id and status = 'SETTLED';
  v_after := jsonb_build_object('head', p_head, 'lines', p_lines);
  insert into public.office_log (van_day_id, module, before_data, after_data) values (d.id, m, v_before, v_after);
  return d.id;
end $$;
grant execute on function public.office_save(bigint, date, text, jsonb, jsonb) to authenticated;
select 'office entry ready' as result;
