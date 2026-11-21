-- =====================================================================
-- FIX ME FUNCTION - CREATE
-- me() listed the staff columns one by one for the SYSTEM row, so adding a column to staff (email)
-- broke it ("each UNION query must have the same number of columns") and nobody could sign in.
-- Same result as before, now independent of the number of staff columns.
-- Revert: FIX ME FUNCTION - REVERT.sql
-- =====================================================================
create or replace function public.me() returns public.staff
language sql stable security definer set search_path to 'public' as $function$
  select s.* from public.staff s where s.auth_user_id = auth.uid() and s.active and s.can_login
  union all
  select (jsonb_populate_record(null::public.staff, jsonb_build_object('name','SYSTEM','role','ADMIN','can_login',true,'active',true,'created_at',now()))).*
   where auth.uid() is null and session_user in ('postgres','supabase_admin')
  limit 1
$function$;
