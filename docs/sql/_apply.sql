-- STAFF DESIGNATION - CREATE
-- Job title shown under the name in the portal (e.g. Inventory Controller). The role (Admin, Accountant ...) still decides access.
alter table public.staff add column if not exists designation text;
update public.staff set designation = 'Inventory Controller' where upper(name) = 'MUSTHAFFIR' and designation is null;

create or replace function public.admin_user_designation(p_id bigint, p_designation text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(array['ADMIN']);
  update public.staff set designation = nullif(trim(coalesce(p_designation,'')),'') where id = p_id;
  if not found then raise exception 'User not found.'; end if;
end $$;
revoke all on function public.admin_user_designation(bigint, text) from public, anon;
grant execute on function public.admin_user_designation(bigint, text) to authenticated;
notify pgrst, 'reload schema';
