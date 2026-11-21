-- APPROVED DEVICES - CREATE.sql (update): no auto-approve of another user's device
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
  -- auto-approve only a user's very first device, and never a device already approved for someone else
  if first and m = 1 and s.role in ('SALESMAN', 'RECEIVER')
     and not exists (select 1 from public.app_devices x where x.device_id = dev and x.staff_id <> s.id and x.approved) then
    update public.app_devices set approved = true, approved_at = now(), approved_by = 'AUTO (first device)' where staff_id = s.id and device_id = dev;
  end if;
  ok := public.device_ok(s.id, s.role);
  return jsonb_build_object('ok', ok, 'code', code, 'error', case when ok then null else
    'This device is not approved for ' || s.name || '. Device code ' || code || '. Ask the admin to approve it in the portal: Admin → Users → Devices.' end);
end $$;
