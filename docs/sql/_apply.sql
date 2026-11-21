-- CASH BALANCE - REVERT : removes what CASH BALANCE - CREATE.sql added.
drop function if exists public.save_cash_balance(bigint, jsonb, boolean);
drop table if exists public.cash_balance;
