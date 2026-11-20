-- USER ADMIN - REVERT : removes the Users page functions. Logins already made stay; staff.email is removed.
drop function if exists public.admin_user_list();
drop function if exists public.admin_user_save(bigint, text, text, bigint, text, text, boolean, text);
alter table public.staff drop column if exists email;
