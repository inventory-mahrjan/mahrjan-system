-- APPROVED DEVICES - REVERT.sql
-- Undoes APPROVED DEVICES - CREATE.sql: me() goes back to the original, devices list and setting removed.

create or replace function public.me() returns public.staff
language sql stable security definer set search_path to 'public' as $$
  select s.* from public.staff s where s.auth_user_id = auth.uid() and s.active and s.can_login
  union all
  select (jsonb_populate_record(null::public.staff, jsonb_build_object('name','SYSTEM','role','ADMIN','can_login',true,'active',true,'created_at',now()))).*
  where auth.uid() is null and session_user in ('postgres','supabase_admin')
  limit 1 $$;

drop function if exists public.device_admin(bigint, text);
drop function if exists public.device_register(text);
drop function if exists public.device_ok(bigint, text);
drop function if exists public.req_device();
drop table if exists public.app_devices;
delete from public.app_settings where key = 'DEVICE_LOCK';
