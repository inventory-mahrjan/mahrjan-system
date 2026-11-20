-- =====================================================================
-- MAHRJAN SYSTEM - APP BRIDGE (CREATE)
-- What the old van-sales app needs from the new database so it can run unchanged:
--   1. van_day.summary            - the salesman SUMMARY post (totals, variance, reason)
--   2. sales_deletes              - the DELETE list (invoices left out until the ERP drops them)
--   3. carton expenses            - CARTON SMALL / BIG from the return count (0.50 / 0.25 each), as before
--   4. app_day                    - van day for expense / collection / summary before boarding
--   5. app_collections            - receipt and invoice checks across salesmen, new customers added
--   6. app_van                    - vehicle number -> van (added if new)
--   7. login_unit                 - which company a username belongs to (login screen)
-- Revert: APP BRIDGE - REVERT.sql
-- =====================================================================
begin;

-- 1. SUMMARY
alter table public.van_day add column if not exists summary jsonb;
create or replace function public.app_summary(p_van_day bigint, p_summary jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare d public.van_day;
begin
  d := public.day_for_update(p_van_day, array['M:days'], array['OPEN','LOADED','RETURNED']);
  update public.van_day set summary = p_summary where id = d.id;
end $$;

-- 2. DELETE list
create table public.sales_deletes (
  id          bigint generated always as identity primary key,
  branch_id   bigint not null references public.branches(id),
  del_date    date not null,
  invoice     text not null,
  user_name   text,
  created_at  timestamptz not null default now(),
  created_by  uuid default auth.uid(),
  unique (branch_id, invoice)
);
alter table public.sales_deletes enable row level security;
grant select on public.sales_deletes to authenticated;
create policy read_branch on public.sales_deletes for select to authenticated using (public.can_branch(branch_id));
create trigger trg_sales_deletes_audit after insert or update or delete on public.sales_deletes for each row execute function public.audit_row();

-- MGAZ-CR-017031 = MGAZ-CR-17031 ; a number alone (35176) matches the invoice ending in it (for that user when given)
create or replace function public.inv_key(v text) returns text language sql immutable as $$
  select case when s ~ '\d+$' then regexp_replace(s, '\d+$', '') || (regexp_match(s, '(\d+)$'))[1]::numeric::text else s end
    from (select upper(regexp_replace(coalesce(v,''), '\s+', '', 'g')) s) x $$;
create or replace function public.is_deleted_invoice(p_branch bigint, p_invoice text, p_user text) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sales_deletes d where d.branch_id = p_branch
     and (public.inv_key(d.invoice) = public.inv_key(p_invoice)
          or (d.invoice ~ '^\d+$' and d.invoice::numeric::text = (regexp_match(regexp_replace(coalesce(p_invoice,''),'\s+','','g'), '(\d+)$'))[1]::numeric::text
              and (coalesce(d.user_name,'') = '' or upper(trim(d.user_name)) = upper(trim(coalesce(p_user,'')))))) ) $$;
-- keep sales_lines.cancelled in step with the list
create or replace function public.sales_lines_deleted() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_deleted_invoice(new.branch_id, new.invoice_no, new.itrade_user) then
    new.cancelled := true; new.cancel_reason := 'DELETE LIST';
  elsif new.cancel_reason = 'DELETE LIST' then
    new.cancelled := false; new.cancel_reason := null;
  end if;
  return new;
end $$;
create trigger trg_sales_lines_deleted before insert or update on public.sales_lines for each row execute function public.sales_lines_deleted();
create or replace function public.app_delete(p_branch bigint, p_date date, p_invoice text, p_user text, p_undo boolean default false)
returns integer language plpgsql security definer set search_path = public as $$
declare v_inv text := upper(regexp_replace(coalesce(p_invoice,''), '\s+', '', 'g')); n integer;
begin
  perform public.require_role(array['ADMIN','ACCOUNTANT','RECEIVER'], p_branch);
  if v_inv = '' then raise exception 'Invoice number is empty'; end if;
  delete from public.sales_deletes where branch_id = p_branch and invoice = v_inv;
  if not p_undo then insert into public.sales_deletes (branch_id, del_date, invoice, user_name) values (p_branch, p_date, v_inv, nullif(trim(p_user),'')); end if;
  update public.sales_lines set cancelled = cancelled          -- fires the trigger, which re-checks the list
   where branch_id = p_branch and (public.inv_key(invoice_no) = public.inv_key(v_inv) or invoice_no ~ (v_inv || '$') or cancel_reason = 'DELETE LIST');
  get diagnostics n = row_count;
  return n;
end $$;

-- 3. CARTON expenses from the return count (old: CARTON SMALL 0.50, CARTON BIG 0.25 each, note "29 @ 0.25")
create or replace function public.van_day_cartons() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'INSERT') or new.carton_small is distinct from old.carton_small or new.carton_big is distinct from old.carton_big then
    delete from public.expenses where van_day_id = new.id and expense_type in ('CARTON SMALL','CARTON BIG');
    if coalesce(new.carton_small,0) > 0 then insert into public.expenses (van_day_id, expense_type, amount, note)
      values (new.id, 'CARTON SMALL', round(new.carton_small * 0.50, 2), new.carton_small || ' @ 0.50'); end if;
    if coalesce(new.carton_big,0) > 0 then insert into public.expenses (van_day_id, expense_type, amount, note)
      values (new.id, 'CARTON BIG', round(new.carton_big * 0.25, 2), new.carton_big || ' @ 0.25'); end if;
  end if;
  return new;
end $$;
create trigger trg_van_day_cartons after insert or update of carton_small, carton_big on public.van_day for each row execute function public.van_day_cartons();
-- the salesman's expense post no longer removes the receiver's carton lines
do $$ declare d text; begin
  d := pg_get_functiondef('public.save_expenses'::regproc);
  if position('expense_type not in' in d) = 0 then
    d := replace(d, 'delete from public.expenses where van_day_id = d.id;', 'delete from public.expenses where van_day_id = d.id and expense_type not in (''CARTON SMALL'',''CARTON BIG'');');
    execute d;
  end if;
end $$;

-- 4. van day for posts made before boarding (expense, collection, summary)
create or replace function public.app_day(p_salesman bigint, p_date date)
returns bigint language plpgsql security definer set search_path = public as $$
declare s public.staff; v_id bigint;
begin
  select * into s from public.staff where id = p_salesman and role = 'SALESMAN';
  if not found then raise exception 'Salesman not found'; end if;
  perform public.require_role(array['M:days'], s.branch_id);
  if public.my_role() = 'SALESMAN' and public.my_staff_id() <> p_salesman then raise exception 'You can only post for yourself'; end if;
  insert into public.van_day (branch_id, business_date, salesman_id, status) values (s.branch_id, p_date, p_salesman, 'OPEN')
  on conflict (salesman_id, business_date) do nothing;
  select id into v_id from public.van_day where salesman_id = p_salesman and business_date = p_date;
  return v_id;
end $$;

-- 5. COLLECTION as the old app posts it: rows [{tran, invoice, head, customer, mode, amount}]
create or replace function public.app_collections(p_van_day bigint, p_rows jsonb, p_allow_dup boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.van_day; r jsonb; v_cust bigint; v_twice text; v_used text; v_dups jsonb;
begin
  d := public.day_for_update(p_van_day, array['M:days'], array['OPEN','LOADED','RETURNED']);
  -- one receipt = one invoice
  select string_agg(k, ', ') into v_twice from (select ltrim(trim(x->>'tran'),'0') k from jsonb_array_elements(p_rows) x
     where coalesce(trim(x->>'tran'),'') <> '' group by 1 having count(*) > 1) z;
  if v_twice is not null then return jsonb_build_object('ok', false, 'error', 'One receipt = one invoice. Receipt ' || v_twice || ' is on more than one invoice.'); end if;
  select string_agg('Receipt ' || ltrim(c.receipt_no,'0') || ' was used for ' || coalesce(c.invoice_no,'') || ' on ' || vd.business_date, '; ') into v_used
    from public.collections c join public.van_day vd on vd.id = c.van_day_id
   where vd.salesman_id = d.salesman_id and c.van_day_id <> d.id
     and ltrim(c.receipt_no,'0') in (select ltrim(trim(x->>'tran'),'0') from jsonb_array_elements(p_rows) x where coalesce(trim(x->>'tran'),'') <> '');
  if v_used is not null then return jsonb_build_object('ok', false, 'error', 'Receipt number already used (one receipt = one invoice). ' || v_used || '.'); end if;
  if not p_allow_dup then
    select jsonb_agg(jsonb_build_object('invoice', upper(c.invoice_no), 'date', vd.business_date, 'salesman', s.name, 'amount', c.amount)) into v_dups
      from public.collections c join public.van_day vd on vd.id = c.van_day_id join public.staff s on s.id = vd.salesman_id
     where vd.branch_id = d.branch_id and c.van_day_id <> d.id and coalesce(c.invoice_no,'') <> ''
       and upper(trim(c.invoice_no)) in (select upper(trim(x->>'invoice')) from jsonb_array_elements(p_rows) x);
    if v_dups is not null then return jsonb_build_object('ok', false, 'error', 'DUP_INVOICE', 'dups', v_dups); end if;
  end if;
  delete from public.collections where van_day_id = d.id;
  for r in select * from jsonb_array_elements(p_rows) loop
    if coalesce((r->>'amount')::numeric, 0) <= 0 then continue; end if;
    select id into v_cust from public.customers where branch_id = d.branch_id and itrade_code = nullif(trim(r->>'head'),'') limit 1;
    if v_cust is null then select id into v_cust from public.customers where branch_id = d.branch_id and upper(name) = upper(trim(r->>'customer')) limit 1; end if;
    if v_cust is null then
      insert into public.customers (itrade_code, name, branch_id) values (nullif(trim(r->>'head'),''), trim(r->>'customer'), d.branch_id) returning id into v_cust;
      insert into public.customer_assignment (customer_id, salesman_id, route_id, from_date, reason) values (v_cust, d.salesman_id, d.route_id, d.business_date, 'Added from app collection');
    end if;
    insert into public.collections (van_day_id, receipt_no, invoice_no, customer_id, mode, amount)
    values (d.id, coalesce(nullif(trim(r->>'tran'),''), 'NA-' || md5(r::text)), nullif(upper(trim(r->>'invoice')),''), v_cust,
            case when upper(r->>'mode') in ('CASH','CHEQUE','TRANSFER') then upper(r->>'mode') else 'CASH' end, (r->>'amount')::numeric);
  end loop;
  return jsonb_build_object('ok', true, 'written', jsonb_array_length(p_rows));
end $$;

-- 6. vehicle number -> van
create or replace function public.app_van(p_branch bigint, p_van_no text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint; v text := upper(regexp_replace(coalesce(p_van_no,''), '\s+', '', 'g'));
begin
  perform public.require_role(array['M:load'], p_branch);
  if v !~ '^\d{1,5}$' then raise exception 'Vehicle number must be numbers only, max 5 digits (now "%").', p_van_no; end if;
  select id into v_id from public.vans where van_no = v and branch_id = p_branch;
  if v_id is null then select id into v_id from public.vans where van_no = v; end if;
  if v_id is null then insert into public.vans (van_no, branch_id) values (v, p_branch) returning id into v_id; end if;
  return v_id;
end $$;

-- 7. login screen: company of a username (unknown names answer AL QUOZ, as before)
create or replace function public.login_unit(p_username text) returns text
  language sql stable security definer set search_path = public as $$
  select coalesce((select case when s.branch_id is null then 'BOTH' when b.code = 'MGT' then 'AJMAN' else 'AL QUOZ' end
                     from public.staff s left join public.branches b on b.id = s.branch_id
                    where s.active and s.can_login and upper(regexp_replace(s.name,'[^A-Za-z0-9]','','g')) = upper(regexp_replace(coalesce(p_username,''),'[^A-Za-z0-9]','','g'))
                    limit 1), 'AL QUOZ') $$;

revoke execute on function public.app_summary, public.app_delete, public.app_day, public.app_collections, public.app_van, public.is_deleted_invoice from public, anon;
grant execute on function public.app_summary, public.app_delete, public.app_day, public.app_collections, public.app_van to authenticated;
grant execute on function public.login_unit to anon, authenticated;
commit;
