-- STAFF DESIGNATION - REVERT
drop function if exists public.admin_user_designation(bigint, text);
alter table public.staff drop column if exists designation;
notify pgrst, 'reload schema';
