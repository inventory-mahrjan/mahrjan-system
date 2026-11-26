-- DELETE BILL MATCH - REVERT (the restored invoice MGAZ-CR-039728 stays restored; delete it again from Office entry if needed)
create or replace function public.app_delete(p_branch bigint, p_date date, p_invoice text, p_user text, p_undo boolean default false)
returns integer language plpgsql security definer set search_path to 'public' as $function$
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
end $function$;
create or replace function public.sales_lines_deleted() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_deleted_invoice(new.branch_id, new.invoice_no, new.itrade_user) then
    new.cancelled := true; new.cancel_reason := 'DELETE LIST';
  elsif new.cancel_reason = 'DELETE LIST' then
    new.cancelled := false; new.cancel_reason := null;
  end if;
  return new;
end $$;
drop function if exists public.sales_line_owner_ok(text, date, public.sales_lines);
alter table public.sales_deletes drop column if exists strict;
notify pgrst, 'reload schema';
