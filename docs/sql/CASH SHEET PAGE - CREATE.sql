-- CASH SHEET PAGE - CREATE.sql (25 Nov 2026)
-- New portal page "Cash sheet" (admin / accountant):
--  * cash count rows (currency + count) kept one month, counted total kept always
--  * every cash entry on a day older than 5 days is locked (opening balance, cash count, cash book)
-- Undo with: CASH SHEET PAGE - REVERT.sql
create table if not exists public.cash_count (
  branch_id int not null, count_date date not null, line_no int not null, denom numeric(10,2) not null, qty numeric(12,2) not null,
  primary key (branch_id, count_date, line_no));
alter table public.cash_count enable row level security;
drop policy if exists read_cash_count on public.cash_count;
create policy read_cash_count on public.cash_count for select to authenticated using (can_branch(branch_id));
create table if not exists public.cash_count_total (
  branch_id int not null, count_date date not null, total numeric(14,2) not null, updated_at timestamptz not null default now(), updated_by uuid default auth.uid(),
  primary key (branch_id, count_date));
alter table public.cash_count_total enable row level security;
drop policy if exists read_cash_count_total on public.cash_count_total;
create policy read_cash_count_total on public.cash_count_total for select to authenticated using (can_branch(branch_id));

create or replace function public.cash_day_locked(p_date date) returns boolean language sql stable as $$
  select p_date < (now() at time zone 'Asia/Dubai')::date - 5 $$;

create or replace function public.save_cash_count(p_branch int, p_date date, p_rows jsonb) returns numeric
language plpgsql security definer set search_path = public as $$
declare t numeric;
begin
  if my_role() not in ('ADMIN', 'ACCOUNTANT') or not can_branch(p_branch) then raise exception 'Only admin or accountant can enter the cash count.'; end if;
  if cash_day_locked(p_date) then raise exception 'This day is locked (older than 5 days).'; end if;
  delete from public.cash_count where branch_id = p_branch and count_date = p_date;
  insert into public.cash_count (branch_id, count_date, line_no, denom, qty)
    select p_branch, p_date, o::int, (x->>'denom')::numeric, (x->>'qty')::numeric from jsonb_array_elements(coalesce(p_rows, '[]')) with ordinality r(x, o)
     where coalesce((x->>'qty')::numeric, 0) <> 0 and coalesce((x->>'denom')::numeric, 0) > 0;
  select coalesce(sum(denom * qty), 0) into t from public.cash_count where branch_id = p_branch and count_date = p_date;
  if exists (select 1 from public.cash_count where branch_id = p_branch and count_date = p_date) then
    insert into public.cash_count_total (branch_id, count_date, total) values (p_branch, p_date, round(t, 2))
      on conflict (branch_id, count_date) do update set total = excluded.total, updated_at = now(), updated_by = auth.uid();
  else delete from public.cash_count_total where branch_id = p_branch and count_date = p_date; end if;
  delete from public.cash_count where count_date < (now() at time zone 'Asia/Dubai')::date - 31;   -- count rows kept one month, totals kept
  return round(t, 2);
end $$;
revoke all on function public.save_cash_count(int, date, jsonb) from public, anon;
grant execute on function public.save_cash_count(int, date, jsonb) to authenticated;

-- opening balance: same 5-day lock
create or replace function public.save_cash_opening(p_branch int, p_date date, p_amount numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if my_role() not in ('ADMIN', 'ACCOUNTANT') or not can_branch(p_branch) then raise exception 'Only admin or accountant can set the opening balance.'; end if;
  if cash_day_locked(p_date) then raise exception 'This day is locked (older than 5 days).'; end if;
  if p_amount is null then delete from public.cash_opening where branch_id = p_branch and open_date = p_date;
  else insert into public.cash_opening (branch_id, open_date, amount) values (p_branch, p_date, round(p_amount, 2))
       on conflict (branch_id, open_date) do update set amount = excluded.amount, updated_at = now(), updated_by = auth.uid(); end if;
end $$;

-- cash book (petty cash lines): admin or accountant, locked after 5 days (was: 3 days, admin any day)
create or replace function public.save_petty_cash(p_branch bigint, p_date date, p_lines jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  perform public.require_role(array['M:pc'], p_branch);
  if public.my_role() not in ('ADMIN', 'ACCOUNTANT') then raise exception 'Only admin or accountant can change the cash book.'; end if;
  if public.cash_day_locked(p_date) then raise exception 'This day is locked (older than 5 days).'; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p_lines,'[]')) x where coalesce(trim(x->>'party'),'') = '' or coalesce((x->>'amount')::numeric,0) <= 0) then
    raise exception 'Every line needs particulars and an amount above zero'; end if;
  delete from public.petty_cash where branch_id = p_branch and entry_date = p_date;
  insert into public.petty_cash (branch_id, entry_date, line_no, line_type, ref, party, note, for_date, amount)
  select p_branch, p_date, o::int, x->>'line_type', nullif(trim(x->>'ref'),''), trim(x->>'party'), nullif(trim(x->>'note'),''), nullif(x->>'for_date','')::date, (x->>'amount')::numeric
    from jsonb_array_elements(coalesce(p_lines,'[]')) with ordinality t(x, o);
  get diagnostics n = row_count; return n;
end $$;
grant select on public.cash_count, public.cash_count_total, public.cash_opening to authenticated;
notify pgrst, 'reload schema';
select 'ok' as result;
