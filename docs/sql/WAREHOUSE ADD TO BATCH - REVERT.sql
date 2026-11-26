-- WAREHOUSE ADD TO BATCH - REVERT
-- Additional-issue lines stay in their batches (they are real issues); only the function and the column marker are removed.
drop function if exists public.wh_issue_add(bigint, bigint, jsonb);
alter table public.wh_lines drop column if exists issue_no;
notify pgrst, 'reload schema';
