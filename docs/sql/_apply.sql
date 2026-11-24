-- CUSTOMER 45 DAY BASE - CREATE.sql (24 Nov 2026)
-- The last-visit dates from the Customer Visit Status of 04-Nov-2026 are loaded into customer_visit_base
-- (loaded from the browser, not kept here). That report listed only customers with a sale in the 45 days
-- before 04-Nov, so a customer not in it and not billed since is taken as last visited before 20-Sep-2026.
-- The temporary "1 Nov" floor is removed. Undo with: CUSTOMER 45 DAY BASE - REVERT.sql
create or replace function public.customer_last_visit() returns table (customer_id bigint, last_visit date)
language sql stable security definer set search_path = public as $$
  select c.id, coalesce(greatest(s.last, b.last_visit, case when c.created_at > timestamptz '2026-11-22' then c.created_at::date end), date '2026-09-19')
    from public.customers c
    left join (select customer_id, max(tran_date) last from public.sales_lines where tran_type = 'CR' and not cancelled and customer_id is not null group by 1) s on s.customer_id = c.id
    left join public.customer_visit_base b on b.customer_id = c.id $$;
update public.customers c set active = (v.last_visit >= (now() at time zone 'Asia/Dubai')::date - 45), updated_at = now()
  from public.customer_last_visit() v where v.customer_id = c.id and c.active is distinct from (v.last_visit >= (now() at time zone 'Asia/Dubai')::date - 45);
select count(*) filter (where active) || ' active, ' || count(*) filter (where not active) || ' inactive' as result from public.customers;
