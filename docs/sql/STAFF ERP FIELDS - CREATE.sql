-- STAFF ERP FIELDS - CREATE
-- A salesman has three names in iTrade (ERP): the ERP user, the Sales Executive and his van warehouse.
--   itrade_name   = Sales Executive (already there, used by the sales import)
--   erp_user      = iTrade user who makes his bills
--   erp_warehouse = his van warehouse in iTrade
alter table public.staff add column if not exists erp_user text;
alter table public.staff add column if not exists erp_warehouse text;
update public.staff set erp_user = itrade_name where role = 'SALESMAN' and erp_user is null and itrade_name is not null;

create or replace function public.admin_user_erp(p_id bigint, p_erp_user text, p_erp_warehouse text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(array['ADMIN']);
  update public.staff set erp_user = nullif(upper(trim(coalesce(p_erp_user,''))),''), erp_warehouse = nullif(upper(trim(coalesce(p_erp_warehouse,''))),'')
   where id = p_id;
  if not found then raise exception 'User not found.'; end if;
end $$;
revoke all on function public.admin_user_erp(bigint, text, text) from public, anon;
grant execute on function public.admin_user_erp(bigint, text, text) to authenticated;
select 'staff ERP fields ready' as result;
