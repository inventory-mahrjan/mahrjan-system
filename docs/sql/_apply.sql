-- =====================================================================
-- CASH BALANCE - CREATE
-- Same as the CASH BALANCE tab of the unit sheet: one row per branch / day
-- (CLOSE DATE, EXPECTED, COUNTED, CLOSING). The cash sheet opening is worked
-- out from the latest counted or locked day, exactly like openingFor() of the
-- old portal. Revert: CASH BALANCE - REVERT.sql
-- =====================================================================
create table if not exists public.cash_balance (
  id          bigint generated always as identity unique,
  branch_id   bigint not null references public.branches(id),
  close_date  date not null,
  expected    numeric(14,2),
  counted     numeric(14,2),
  closing     numeric(14,2),
  updated_at  timestamptz not null default now(),
  updated_by  uuid default auth.uid(),
  primary key (branch_id, close_date)
);
alter table public.cash_balance enable row level security;
grant select on public.cash_balance to authenticated;
drop policy if exists read_branch on public.cash_balance;
create policy read_branch on public.cash_balance for select to authenticated using (public.can_branch(branch_id));

-- p_rows = [{"date":"2026-11-01","expected":123.45,"counted":0,"closing":123.45}, ...]
-- p_only_new = true: rows already there are kept (used by the portal for locked days).
create or replace function public.save_cash_balance(p_branch bigint, p_rows jsonb, p_only_new boolean default false)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  perform public.require_role(array['ADMIN','ACCOUNTANT'], p_branch);
  insert into public.cash_balance (branch_id, close_date, expected, counted, closing)
  select p_branch, (r->>'date')::date, nullif(r->>'expected','')::numeric, nullif(r->>'counted','')::numeric, nullif(r->>'closing','')::numeric
  from jsonb_array_elements(p_rows) r
  where coalesce(r->>'date','') <> ''
  on conflict (branch_id, close_date) do update
    set expected = excluded.expected, counted = excluded.counted, closing = excluded.closing, updated_at = now(), updated_by = auth.uid()
    where not p_only_new;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.save_cash_balance(bigint, jsonb, boolean) from public, anon;
grant execute on function public.save_cash_balance(bigint, jsonb, boolean) to authenticated;
