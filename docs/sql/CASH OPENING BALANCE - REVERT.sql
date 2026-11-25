-- CASH OPENING BALANCE - REVERT.sql
drop function if exists public.save_cash_opening(int, date, numeric);
drop table if exists public.cash_opening;
