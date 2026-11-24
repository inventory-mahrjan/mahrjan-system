-- CUSTOMER 45 DAY INACTIVE - CREATE.sql (24 Nov 2026)
-- A customer with no sales invoice (visit) in the last 45 days is marked inactive; billed again -> active again.
-- Last visit = latest of: last CR invoice in the system, the last visit date given as of 1 Nov (customer_visit_base),
-- the day the customer was created, and 1 Nov 2026 (sales in the system start 2 Nov).
-- Runs by itself after every sales import (statement trigger on sales_lines) - no timer needed.
-- Old active flags kept in customers_active_backup. Undo with: CUSTOMER 45 DAY INACTIVE - REVERT.sql
create table if not exists public.customer_visit_base (customer_id bigint primary key references public.customers(id) on delete cascade, last_visit date not null);
alter table public.customer_visit_base enable row level security;
drop policy if exists read_base on public.customer_visit_base;
create policy read_base on public.customer_visit_base for select to authenticated using (true);

create table if not exists public.customers_active_backup as select id, active, now() saved_at from public.customers where false;
alter table public.customers_active_backup enable row level security;
insert into public.customers_active_backup (id, active) select id, active from public.customers
  where not exists (select 1 from public.customers_active_backup b where b.id = customers.id);

create or replace function public.customer_last_visit() returns table (customer_id bigint, last_visit date)
language sql stable security definer set search_path = public as $$
  select c.id, greatest(s.last, b.last_visit, c.created_at::date, date '2026-11-01')
    from public.customers c
    left join (select customer_id, max(tran_date) last from public.sales_lines where tran_type = 'CR' and not cancelled and customer_id is not null group by 1) s on s.customer_id = c.id
    left join public.customer_visit_base b on b.customer_id = c.id $$;

create or replace function public.customers_visit_status() returns trigger
language plpgsql security definer set search_path = public as $$
declare d date := (now() at time zone 'Asia/Dubai')::date;
begin
  update public.customers c set active = (v.last_visit >= d - 45), updated_at = now()
    from public.customer_last_visit() v
   where v.customer_id = c.id and c.active is distinct from (v.last_visit >= d - 45);
  return null;
end $$;
revoke all on function public.customers_visit_status() from public, anon, authenticated;
revoke all on function public.customer_last_visit() from public, anon;
grant execute on function public.customer_last_visit() to authenticated;

drop trigger if exists trg_customers_visit_status on public.sales_lines;
create trigger trg_customers_visit_status after insert or update on public.sales_lines
  for each statement execute function public.customers_visit_status();

-- run once now
do $$ begin perform 1; update public.customers c set active = (v.last_visit >= (now() at time zone 'Asia/Dubai')::date - 45)
  from public.customer_last_visit() v where v.customer_id = c.id and c.active is distinct from (v.last_visit >= (now() at time zone 'Asia/Dubai')::date - 45); end $$;
select count(*) filter (where active) || ' active, ' || count(*) filter (where not active) || ' inactive' as result from public.customers;
