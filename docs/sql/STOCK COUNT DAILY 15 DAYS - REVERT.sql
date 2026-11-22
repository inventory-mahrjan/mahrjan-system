-- STOCK COUNT DAILY 15 DAYS - REVERT.sql
-- Stops the automatic clean-up of daily stock count batches. Batches already removed do not come back.
drop trigger if exists trg_sc_purge_daily on public.sc_batches;
drop function if exists public.sc_purge_daily_trg();
drop function if exists public.sc_purge_daily(int);
