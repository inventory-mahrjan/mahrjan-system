-- MAHRJAN SYSTEM - WAREHOUSE (REVERT): removes the warehouse tables, view and functions.
begin;
drop function if exists public.wh_cancel, public.wh_return, public.wh_issue, public.wh_check_duty;
drop view if exists public.v_fg_bom;
drop table if exists public.wh_lines;
drop table if exists public.wh_batches;
commit;
