-- MAHRJAN SYSTEM - PETTY CASH (REVERT) : removes the petty cash table and its functions
begin;
drop function if exists public.save_petty_cash(bigint, date, jsonb);
drop function if exists public.petty_opening(bigint, date);
drop table if exists public.petty_cash;
commit;
