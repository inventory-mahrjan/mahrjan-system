-- =====================================================================
-- MAHRJAN SYSTEM - STAFF LOGINS (CREATE)
-- Creates one login for every active staff member (all roles except PACKER) who has none yet.
--   username = staff name in lowercase, spaces removed      (e.g. KAREEM -> kareem, MUHAMMED ALI -> muhammedali)
--   email    = username@mahrjan.app
--   branch / unit and role come from the staff record (Al Quoz, Ajman or both).
-- BEFORE RUNNING: type the starting password on the line marked  <<< TYPE PASSWORD >>>
-- Revert: STAFF LOGINS - REVERT.sql
-- =====================================================================
do $$
declare
  v_pw  text := '';            -- <<< TYPE PASSWORD >>> between the quotes
  s     record;
  v_uid uuid;
  v_em  text;
  v_out text := '';
begin
  if length(v_pw) < 6 then raise exception 'Type a password of at least 6 characters on the marked line first'; end if;
  for s in select id, name, role from public.staff
            where active and role <> 'PACKER' and auth_user_id is null order by name loop
    v_em := lower(regexp_replace(s.name, '[^A-Za-z0-9]', '', 'g')) || '@mahrjan.app';
    if exists (select 1 from auth.users where email = v_em) then
      v_out := v_out || s.name || ' (email already used: ' || v_em || '), '; continue; end if;
    v_uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_em,
            extensions.crypt(v_pw, extensions.gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}', jsonb_build_object('staff', s.name), now(), now(), '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), v_uid, v_uid::text, jsonb_build_object('sub', v_uid::text, 'email', v_em, 'email_verified', true),
            'email', now(), now(), now());
    update public.staff set can_login = true, auth_user_id = v_uid where id = s.id;
  end loop;
  if v_out <> '' then raise notice 'Skipped: %', v_out; end if;
end $$;

-- list of logins (username to give each person)
select s.name, s.role, coalesce(b.name, 'Both branches') as unit,
       split_part(u.email, '@', 1) as username
  from public.staff s join auth.users u on u.id = s.auth_user_id
  left join public.branches b on b.id = s.branch_id
 order by unit, s.role, s.name;
