-- CASH SHEET PAGE - REVERT.sql : back to the earlier rules (cash book: older than 3 days admin only; opening: no lock), count tables dropped
create or replace function public.save_petty_cash(p_branch bigint, p_date date, p_lines jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  perform public.require_role(array['M:pc'], p_branch);
  if public.my_role() <> 'ADMIN' and p_date < (now() at time zone 'Asia/Dubai')::date - 3 then raise exception 'Days older than 3 days can only be changed by ADMIN'; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p_lines,'[]')) x where coalesce(trim(x->>'party'),'') = '' or coalesce((x->>'amount')::numeric,0) <= 0) then
    raise exception 'Every line needs particulars and an amount above zero'; end if;
  delete from public.petty_cash where branch_id = p_branch and entry_date = p_date;
  insert into public.petty_cash (branch_id, entry_date, line_no, line_type, ref, party, note, for_date, amount)
  select p_branch, p_date, o::int, x->>'line_type', nullif(trim(x->>'ref'),''), trim(x->>'party'), nullif(trim(x->>'note'),''), nullif(x->>'for_date','')::date, (x->>'amount')::numeric
    from jsonb_array_elements(coalesce(p_lines,'[]')) with ordinality t(x, o);
  get diagnostics n = row_count; return n;
end $$;
create or replace function public.save_cash_opening(p_branch int, p_date date, p_amount numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if my_role() not in ('ADMIN', 'ACCOUNTANT') or not can_branch(p_branch) then raise exception 'Only admin or accountant can set the opening balance.'; end if;
  if p_amount is null then delete from public.cash_opening where branch_id = p_branch and open_date = p_date;
  else insert into public.cash_opening (branch_id, open_date, amount) values (p_branch, p_date, round(p_amount, 2))
       on conflict (branch_id, open_date) do update set amount = excluded.amount, updated_at = now(), updated_by = auth.uid(); end if;
end $$;
drop function if exists public.save_cash_count(int, date, jsonb);
drop function if exists public.cash_day_locked(date);
drop table if exists public.cash_count;
drop table if exists public.cash_count_total;
notify pgrst, 'reload schema';
