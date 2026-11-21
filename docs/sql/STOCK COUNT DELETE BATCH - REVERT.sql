-- STOCK COUNT DELETE BATCH - REVERT
drop function if exists public.sc_delete_batch(bigint);
select 'sc_delete_batch removed' as result;
