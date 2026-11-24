-- CUSTOMER 45 DAY INACTIVE - REVERT.sql : stops the 45-day rule and puts back the active flags saved before it
drop trigger if exists trg_customers_visit_status on public.sales_lines;
drop function if exists public.customers_visit_status();
drop function if exists public.customer_last_visit();
update public.customers c set active = b.active from public.customers_active_backup b where b.id = c.id;
-- customer_visit_base (the 1 Nov last-visit dates) is kept; drop it by hand if not needed:
-- drop table public.customer_visit_base;
