-- CASH OPENING BALANCE - CREATE.sql (25 Nov 2026)
-- Opening cash balance typed on the daily cash sheet (portal Daily sheets -> Cash sheet), one per company and date.
-- Undo with: CASH OPENING BALANCE - REVERT.sql
create table if not exists public.cash_opening (
  branch_id int not null, open_date date not null, amount numeric(14,2) not null,
  updated_at timestamptz not null default now(), updated_by uuid default auth.uid(),
  primary key (branch_id, open_date));
alter table public.cash_opening enable row level security;
drop policy if exists read_cash_opening on public.cash_opening;
create policy read_cash_opening on public.cash_opening for select to authenticated using (can_branch(branch_id));
create or replace function public.save_cash_opening(p_branch int, p_date date, p_amount numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if my_role() not in ('ADMIN', 'ACCOUNTANT') or not can_branch(p_branch) then raise exception 'Only admin or accountant can set the opening balance.'; end if;
  if p_amount is null then delete from public.cash_opening where branch_id = p_branch and open_date = p_date;
  else insert into public.cash_opening (branch_id, open_date, amount) values (p_branch, p_date, round(p_amount, 2))
       on conflict (branch_id, open_date) do update set amount = excluded.amount, updated_at = now(), updated_by = auth.uid(); end if;
end $$;
revoke all on function public.save_cash_opening(int, date, numeric) from public, anon;
grant execute on function public.save_cash_opening(int, date, numeric) to authenticated;
select 'ok' as result;
