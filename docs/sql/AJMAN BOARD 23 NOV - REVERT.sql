-- AJMAN BOARD 23 NOV - REVERT.sql
-- Undo the 23-Nov-2026 Ajman board loaded from the old app sheet (AJMAN STORE ISSUE 8):
-- removes the loading lines and resets those van days to OPEN (only days with no return posted).
delete from public.loading_lines where van_day_id in (select id from public.van_day where branch_id = 2 and business_date = '2026-11-23'
   and not exists (select 1 from public.return_lines r where r.van_day_id = van_day.id));
update public.van_day set status = 'OPEN', start_km = null, load_time = null, load_temp = null
 where branch_id = 2 and business_date = '2026-11-23' and status = 'LOADED'
   and not exists (select 1 from public.loading_lines l where l.van_day_id = van_day.id);
