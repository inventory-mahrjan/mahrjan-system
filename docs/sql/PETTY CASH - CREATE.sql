-- =====================================================================
-- MAHRJAN SYSTEM - PETTY CASH (CREATE)
-- Office cash book per branch and day: receipts, payments, allowances, bank deposits,
-- suspense given / cleared. Opening balance = all earlier lines (in - out).
-- =====================================================================
begin;

create table public.petty_cash (
  id          bigint generated always as identity primary key,
  branch_id   bigint not null references public.branches(id),
  entry_date  date not null,
  line_no     integer not null,
  line_type   text not null check (line_type in ('RECEIPT','PAYMENT','FOOD ALLOWANCE','TRAVEL ALLOWANCE','DEPOSIT','SUSPENSE','SUSPENSE CLEARED')),
  ref         text,
  party       text not null,
  note        text,
  for_date    date,
  amount      numeric(12,2) not null check (amount > 0),
  direction   smallint generated always as (case when line_type in ('RECEIPT','SUSPENSE CLEARED') then 1 else -1 end) stored,
  created_at  timestamptz not null default now(),
  created_by  uuid default auth.uid(),
  updated_at  timestamptz,
  updated_by  uuid
);
create index petty_cash_day_idx on public.petty_cash (branch_id, entry_date);
create trigger trg_petty_cash_upd before update on public.petty_cash for each row execute function public.set_updated();
create trigger trg_petty_cash_audit after insert or update or delete on public.petty_cash for each row execute function public.audit_row();
alter table public.petty_cash enable row level security;
grant select on public.petty_cash to authenticated;
create policy read_branch on public.petty_cash for select to authenticated
  using (public.can_branch(branch_id) and public.my_role() in ('ADMIN','ACCOUNTANT','VIEWER'));

-- replaces the lines of one branch / day.  p_lines = [{"line_type":"PAYMENT","ref":"","party":"","note":"","for_date":null,"amount":12.5}, ...]
-- an ACCOUNTANT can change today and the last 3 days; older days only ADMIN.
create or replace function public.save_petty_cash(p_branch bigint, p_date date, p_lines jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  perform public.require_role(array['ADMIN','ACCOUNTANT'], p_branch);
  if public.my_role() <> 'ADMIN' and p_date < (now() at time zone 'Asia/Dubai')::date - 3 then
    raise exception 'Days older than 3 days can only be changed by ADMIN'; end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p_lines,'[]')) x
              where coalesce(trim(x->>'party'),'') = '' or coalesce((x->>'amount')::numeric,0) <= 0) then
    raise exception 'Every line needs particulars and an amount above zero'; end if;
  delete from public.petty_cash where branch_id = p_branch and entry_date = p_date;
  insert into public.petty_cash (branch_id, entry_date, line_no, line_type, ref, party, note, for_date, amount)
  select p_branch, p_date, o::int, x->>'line_type', nullif(trim(x->>'ref'),''), trim(x->>'party'), nullif(trim(x->>'note'),''),
         nullif(x->>'for_date','')::date, (x->>'amount')::numeric
    from jsonb_array_elements(coalesce(p_lines,'[]')) with ordinality t(x, o);
  get diagnostics n = row_count;
  return n;
end $$;

-- opening balance before a day
create or replace function public.petty_opening(p_branch bigint, p_date date)
returns numeric language sql stable security invoker set search_path = public as $$
  select coalesce(sum(direction * amount),0) from public.petty_cash where branch_id = p_branch and entry_date < p_date
$$;

revoke execute on function public.save_petty_cash, public.petty_opening from public, anon;
grant execute on function public.save_petty_cash, public.petty_opening to authenticated;
commit;
