-- APPROVED DEVICES - CREATE.sql
-- Salesmen and supervisors (RECEIVER) can only work from devices the admin approved.
-- Enforced inside public.me(), which every access rule and app function already uses.
-- Each app/portal install sends its own device id in the x-mj-device header.
-- Setting DEVICE_LOCK (Admin → Settings): 0 = off, 1 = first device of a user is approved
-- automatically, every other device waits for the admin, 2 = the admin approves every device.
-- Undo with: APPROVED DEVICES - REVERT.sql

create table if not exists public.app_devices (
  id bigserial primary key,
  staff_id bigint not null references public.staff(id) on delete cascade,
  device_id text not null,
  label text,
  approved boolean not null default false,
  approved_at timestamptz,
  approved_by text,
  created_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  unique (staff_id, device_id)
);
alter table public.app_devices enable row level security;
grant select on public.app_devices to authenticated;

insert into public.app_settings (key, value, label)
values ('DEVICE_LOCK', 1, 'Device lock for salesmen & supervisors (0 off · 1 first device auto-approved · 2 admin approves every device)')
on conflict (key) do nothing;

create or replace function public.req_device() returns text language sql stable as $$
  select coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-mj-device', '') $$;

create or replace function public.device_ok(p_staff bigint, p_role text) returns boolean
language sql stable security definer set search_path to 'public' as $$
  select case
    when p_role not in ('SALESMAN', 'RECEIVER') then true
    when coalesce((select value from public.app_settings where key = 'DEVICE_LOCK'), 0) = 0 then true
    when exists (select 1 from public.app_devices d where d.staff_id = p_staff and d.approved and d.device_id = public.req_device()) then true
    when coalesce((select value from public.app_settings where key = 'DEVICE_LOCK'), 0) = 1
         and not exists (select 1 from public.app_devices d where d.staff_id = p_staff) then true
    else false end $$;

-- same as before, plus the device check written inline (no extra function call: me() runs once per row in access rules)
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

drop policy if exists admin_read on public.app_devices;
create policy admin_read on public.app_devices for select to authenticated using (public.my_role() = 'ADMIN');

-- called by the app and the portal right after sign-in / on open
create or replace function public.device_register(p_label text default null) returns jsonb
language plpgsql security definer set search_path to 'public' as $$
declare s public.staff; dev text := public.req_device(); m numeric := coalesce((select value from public.app_settings where key = 'DEVICE_LOCK'), 0);
        first boolean; ok boolean; code text;
begin
  select * into s from public.staff where auth_user_id = auth.uid() and active and can_login limit 1;
  if s.id is null then return jsonb_build_object('ok', false, 'error', 'This login is not linked to an active staff member. Ask the admin.'); end if;
  if length(dev) < 8 then
    ok := public.device_ok(s.id, s.role);
    return jsonb_build_object('ok', ok, 'error', case when ok then null else 'This app is out of date. Close it fully and open it again.' end);
  end if;
  code := upper(left(dev, 4) || '-' || substr(dev, 5, 4));
  first := not exists (select 1 from public.app_devices where staff_id = s.id);
  insert into public.app_devices (staff_id, device_id, label) values (s.id, dev, left(p_label, 120))
    on conflict (staff_id, device_id) do update set last_seen = now(), label = coalesce(excluded.label, public.app_devices.label);
  if first and m = 1 and s.role in ('SALESMAN', 'RECEIVER') then
    update public.app_devices set approved = true, approved_at = now(), approved_by = 'AUTO (first device)' where staff_id = s.id and device_id = dev;
  end if;
  ok := public.device_ok(s.id, s.role);
  return jsonb_build_object('ok', ok, 'code', code, 'error', case when ok then null else
    'This device is not approved for ' || s.name || '. Device code ' || code || '. Ask the admin to approve it in the portal: Admin → Users → Devices.' end);
end $$;

-- admin: APPROVE / BLOCK / DELETE a device
create or replace function public.device_admin(p_id bigint, p_action text) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if public.my_role() is distinct from 'ADMIN' then raise exception 'Only the admin can approve devices'; end if;
  if upper(p_action) = 'APPROVE' then update public.app_devices set approved = true, approved_at = now(), approved_by = (public.me()).name where id = p_id;
  elsif upper(p_action) = 'BLOCK' then update public.app_devices set approved = false, approved_at = now(), approved_by = (public.me()).name where id = p_id;
  elsif upper(p_action) = 'DELETE' then delete from public.app_devices where id = p_id;
  else raise exception 'Unknown action %', p_action; end if;
end $$;

revoke all on function public.device_register(text), public.device_admin(bigint, text), public.device_ok(bigint, text) from public, anon;
grant execute on function public.device_register(text), public.device_admin(bigint, text), public.device_ok(bigint, text), public.req_device() to authenticated;
