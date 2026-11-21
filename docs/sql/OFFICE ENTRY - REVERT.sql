-- OFFICE ENTRY - REVERT
drop function if exists public.office_save(bigint, date, text, jsonb, jsonb);
drop table if exists public.office_log;
select 'office entry removed' as result;
