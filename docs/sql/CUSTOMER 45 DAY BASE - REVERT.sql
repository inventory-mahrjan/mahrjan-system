-- CUSTOMER 45 DAY BASE - REVERT.sql : back to the 1 Nov floor, removes the 04-Nov dates, re-checks active
create or replace function public.customer_last_visit() returns table (customer_id bigint, last_visit date)
language sql stable security definer set search_path = public as $$
  select c.id, greatest(s.last, b.last_visit, case when c.created_at > timestamptz '2026-11-22' then c.created_at::date end, date '2026-11-01')
    from public.customers c
    left join (select customer_id, max(tran_date) last from public.sales_lines where tran_type = 'CR' and not cancelled and customer_id is not null group by 1) s on s.customer_id = c.id
    left join public.customer_visit_base b on b.customer_id = c.id $$;
delete from public.customer_visit_base where true;
update public.customers c set active = (v.last_visit >= (now() at time zone 'Asia/Dubai')::date - 45), updated_at = now()
  from public.customer_last_visit() v where v.customer_id = c.id and c.active is distinct from (v.last_visit >= (now() at time zone 'Asia/Dubai')::date - 45);
