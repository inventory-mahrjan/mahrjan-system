-- =====================================================================
-- USER ADMIN - CREATE
-- Lets the admin add and change users from the portal (like the old portal's Users page):
-- name, role, company, iTrade name, email, active, and the login password.
--   username = name in lowercase, spaces removed (KAREEM -> kareem); login email = username@mahrjan.app
--   Disabled users cannot sign in (their login is blocked until enabled again).
-- Only ADMIN can run it. Passwords are typed by the admin in the portal and stored encrypted.
-- Revert: USER ADMIN - REVERT.sql
-- =====================================================================
alter table public.staff add column if not exists email text;

create or replace function public.admin_user_save(p_id bigint, p_name text, p_role text, p_branch bigint,
  p_itrade text, p_email text, p_active boolean, p_password text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, auth as $$
declare s public.staff; v_em text; v_uid uuid; v_name text := upper(regexp_replace(trim(coalesce(p_name,'')), '\s+', ' ', 'g'));
begin
  perform public.require_role(array['ADMIN']);
  if length(regexp_replace(v_name, '[^A-Z0-9]', '', 'g')) < 3 then raise exception 'Enter a name of at least 3 letters.'; end if;
  if p_role not in ('ADMIN','ACCOUNTANT','RECEIVER','SALESMAN','PACKER','VIEWER') then raise exception 'Choose a role.'; end if;
  if p_password is not null and p_password <> '' and length(p_password) < 6 then raise exception 'Password must be at least 6 characters.'; end if;
  if p_branch is not null and not exists (select 1 from public.branches where id = p_branch) then raise exception 'Choose a company.'; end if;
  v_em := lower(regexp_replace(v_name, '[^A-Za-z0-9]', '', 'g')) || '@mahrjan.app';
  if exists (select 1 from public.staff x where upper(x.name) = v_name and x.id is distinct from p_id) then raise exception '% already exists.', v_name; end if;

  if p_id is null then
    insert into public.staff (name, role, branch_id, itrade_name, email, active, can_login)
    values (v_name, p_role, p_branch, nullif(upper(trim(coalesce(p_itrade,''))),''), nullif(trim(coalesce(p_email,'')),''), coalesce(p_active,true), false)
    returning * into s;
  else
    update public.staff set name = v_name, role = p_role, branch_id = p_branch, itrade_name = nullif(upper(trim(coalesce(p_itrade,''))),''),
           email = nullif(trim(coalesce(p_email,'')),''), active = coalesce(p_active, true)
     where id = p_id returning * into s;
    if s.id is null then raise exception 'User not found.'; end if;
  end if;

  -- login (not for packers)
  if s.role <> 'PACKER' then
    if s.auth_user_id is null and coalesce(p_password,'') <> '' then
      select id into v_uid from auth.users where email = v_em;
      if v_uid is not null and exists (select 1 from public.staff where auth_user_id = v_uid) then raise exception 'The username % is already used by another user.', split_part(v_em,'@',1); end if;
      if v_uid is null then
        v_uid := gen_random_uuid();
        insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                                raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                                confirmation_token, recovery_token, email_change_token_new, email_change)
        values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_em,
                extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
                '{"provider":"email","providers":["email"]}', jsonb_build_object('staff', s.name), now(), now(), '', '', '', '');
        insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
        values (gen_random_uuid(), v_uid, v_uid::text, jsonb_build_object('sub', v_uid::text, 'email', v_em, 'email_verified', true), 'email', now(), now(), now());
      else
        update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now() where id = v_uid;
      end if;
      update public.staff set auth_user_id = v_uid, can_login = true where id = s.id;
      s.auth_user_id := v_uid;
    elsif s.auth_user_id is not null then
      update auth.users set
             email = v_em,
             encrypted_password = case when coalesce(p_password,'') <> '' then extensions.crypt(p_password, extensions.gen_salt('bf')) else encrypted_password end,
             updated_at = now()
       where id = s.auth_user_id;
      update auth.identities set identity_data = identity_data || jsonb_build_object('email', v_em) where user_id = s.auth_user_id and provider = 'email';
      update public.staff set can_login = true where id = s.id;
    end if;
    -- disabled users cannot sign in
    if s.auth_user_id is not null then
      update auth.users set banned_until = case when s.active then null else 'infinity'::timestamptz end where id = s.auth_user_id;
    end if;
  end if;

  return jsonb_build_object('id', s.id, 'name', s.name, 'username', case when s.role = 'PACKER' then null else split_part(v_em,'@',1) end,
                            'login', s.auth_user_id is not null);
end $$;
revoke all on function public.admin_user_save(bigint, text, text, bigint, text, text, boolean, text) from public, anon;
grant execute on function public.admin_user_save(bigint, text, text, bigint, text, text, boolean, text) to authenticated;

-- list for the Users page (admin only): login username and whether the login exists
create or replace function public.admin_user_list()
returns table (id bigint, name text, role text, branch_id bigint, itrade_name text, email text, active boolean, username text, has_login boolean, last_sign_in timestamptz)
language plpgsql security definer set search_path = public, auth as $$
begin
  perform public.require_role(array['ADMIN']);
  return query
  select s.id, s.name, s.role, s.branch_id, s.itrade_name, s.email, s.active,
         case when s.role = 'PACKER' then null else split_part(coalesce(u.email, lower(regexp_replace(s.name, '[^A-Za-z0-9]', '', 'g')) || '@'), '@', 1) end,
         u.id is not null, u.last_sign_in_at
    from public.staff s left join auth.users u on u.id = s.auth_user_id
   order by s.name;
end $$;
revoke all on function public.admin_user_list() from public, anon;
grant execute on function public.admin_user_list() to authenticated;
