-- APPROVED DEVICES - CREATE.sql (update): whole device check inline in me()
create or replace function public.me() returns public.staff
language sql stable security definer set search_path to 'public' as $$
  select s.* from public.staff s where s.auth_user_id = auth.uid() and s.active and s.can_login
    and (s.role not in ('SALESMAN', 'RECEIVER')
      or coalesce((select value from public.app_settings where key = 'DEVICE_LOCK'), 0) = 0
      or exists (select 1 from public.app_devices d where d.staff_id = s.id and d.approved
                 and d.device_id = coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-mj-device', ''))
      or (coalesce((select value from public.app_settings where key = 'DEVICE_LOCK'), 0) = 1
          and not exists (select 1 from public.app_devices d where d.staff_id = s.id)))
  union all
  select (jsonb_populate_record(null::public.staff, jsonb_build_object('name','SYSTEM','role','ADMIN','can_login',true,'active',true,'created_at',now()))).*
  where auth.uid() is null and session_user in ('postgres','supabase_admin')
  limit 1 $$;
