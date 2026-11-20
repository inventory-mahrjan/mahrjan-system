-- =====================================================================
-- MAHRJAN SYSTEM - STAFF LOGINS (REVERT)
-- Removes the logins made by "STAFF LOGINS - CREATE.sql" (marked with raw_user_meta_data.staff).
-- Logins you created yourself in Supabase (e.g. your own admin login) are kept.
-- =====================================================================
begin;
update public.staff set auth_user_id = null, can_login = false
 where auth_user_id in (select id from auth.users where raw_user_meta_data ? 'staff');
delete from auth.identities where user_id in (select id from auth.users where raw_user_meta_data ? 'staff');
delete from auth.users where raw_user_meta_data ? 'staff';
commit;
