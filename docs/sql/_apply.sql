-- DELETE BILL MATCH - CREATE
-- 1. Restores RAMSHAD's invoice MGAZ-CR-039728 (24-Nov-2026, AED 168.00), put on the DELETE list by mistake on 25-Nov
--    under SHINOJ (his real bill was MGAZ-CR-039828). Removing the list entry un-cancels the lines (trg_sales_deletes_apply).
-- 2. A deleted bill must now match the salesman AND the date of the invoice: app_delete refuses an invoice that belongs to
--    another salesman or another date. For an invoice not yet imported, the check runs when it is imported
--    (entries made from now on are only applied to lines of the same salesman and date).
delete from public.sales_deletes where branch_id = 1 and invoice = 'MGAZ-CR-039728' and user_name = 'SHINOJ' and del_date = '2026-11-25';

alter table public.sales_deletes add column if not exists strict boolean not null default false;   -- true = must match salesman + date

create or replace function public.sales_line_owner_ok(p_sm text, p_date date, s public.sales_lines) returns boolean
language sql stable security definer set search_path = public as $$
  select s.tran_date = p_date and (coalesce(trim(p_sm),'') = '' or upper(trim(p_sm)) in (
    upper(coalesce(s.itrade_user,'')), upper(coalesce(s.sales_executive,'')),
    (select upper(coalesce(x,'')) from public.staff st, unnest(array[st.name, st.itrade_name, st.erp_user]) x where st.id = s.salesman_id and upper(coalesce(x,'')) = upper(trim(p_sm)) limit 1))) $$;

create or replace function public.app_delete(p_branch bigint, p_date date, p_invoice text, p_user text, p_undo boolean default false)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare v_inv text := upper(regexp_replace(coalesce(p_invoice,''), '\s+', '', 'g')); n integer; v_bad text;
begin
  perform public.require_role(array['ADMIN','ACCOUNTANT','RECEIVER'], p_branch);
  if v_inv = '' then raise exception 'Invoice number is empty'; end if;
  if not p_undo then
    -- the invoice, if already imported, must be this salesman's and of this date
    select s.invoice_no || ' is ' || coalesce(st.name, s.itrade_user, '?') || '''s invoice of ' || to_char(s.tran_date, 'DD-Mon-YYYY')
      into v_bad
      from public.sales_lines s left join public.staff st on st.id = s.salesman_id
     where s.branch_id = p_branch and public.inv_key(s.invoice_no) = public.inv_key(v_inv)
       and not exists (select 1 from public.sales_lines s2 where s2.branch_id = p_branch and public.inv_key(s2.invoice_no) = public.inv_key(v_inv)
                        and public.sales_line_owner_ok(p_user, p_date, s2))
     limit 1;
    if v_bad is not null then
      raise exception '% — not % on %. Check the invoice number.', v_bad, coalesce(nullif(trim(p_user),''),'this salesman'), to_char(p_date, 'DD-Mon-YYYY');
    end if;
  end if;
  delete from public.sales_deletes where branch_id = p_branch and invoice = v_inv;
  if not p_undo then insert into public.sales_deletes (branch_id, del_date, invoice, user_name, strict) values (p_branch, p_date, v_inv, nullif(trim(p_user),''), true); end if;
  update public.sales_lines set cancelled = cancelled          -- fires the trigger, which re-checks the list
   where branch_id = p_branch and (public.inv_key(invoice_no) = public.inv_key(v_inv) or invoice_no ~ (v_inv || '$') or cancel_reason = 'DELETE LIST');
  get diagnostics n = row_count;
  return n;
end $function$;

-- lines are cancelled by a list entry only if it matches; strict entries must also match salesman + date
create or replace function public.sales_lines_deleted() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.sales_deletes d where d.branch_id = new.branch_id
       and (public.inv_key(d.invoice) = public.inv_key(new.invoice_no)
            or (d.invoice ~ '^\d+$' and d.invoice::numeric::text = (regexp_match(regexp_replace(coalesce(new.invoice_no,''),'\s+','','g'), '(\d+)$'))[1]::numeric::text
                and (coalesce(d.user_name,'') = '' or upper(trim(d.user_name)) = upper(trim(coalesce(new.itrade_user,''))))))
       and (not d.strict or public.sales_line_owner_ok(d.user_name, d.del_date, new))) then
    new.cancelled := true; new.cancel_reason := 'DELETE LIST';
  elsif new.cancel_reason = 'DELETE LIST' then
    new.cancelled := false; new.cancel_reason := null;
  end if;
  return new;
end $$;
notify pgrst, 'reload schema';
