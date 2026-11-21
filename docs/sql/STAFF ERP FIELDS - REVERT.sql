-- STAFF ERP FIELDS - REVERT
drop function if exists public.admin_user_erp(bigint, text, text);
alter table public.staff drop column if exists erp_warehouse;
alter table public.staff drop column if exists erp_user;
select 'staff ERP fields removed' as result;
