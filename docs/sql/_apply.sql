-- APPROVED DEVICES - CREATE.sql (update): device check inline in me()
create or replace function public.me() returns public.staff
language sql stable security definer set search_path to 'public' as $$
  select s.* from public.staff s where s.auth_user_id = auth.uid() and s.active and s.can_login
    and (s.role not in ('SALESMAN', 'RECEIVER') or public.device_ok(s.id, s.role))
  union all
  select (jsonb_populate_record(null::public.staff, jsonb_build_object('name','SYSTEM','role','ADMIN','can_login',true,'active',true,'created_at',now()))).*
  where auth.uid() is null and session_user in ('postgres','supabase_admin')
  limit 1 $$;
