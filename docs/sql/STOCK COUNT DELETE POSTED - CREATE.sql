-- STOCK COUNT DELETE POSTED - CREATE.sql
-- Admin can also delete a POSTED stock count batch (its entries and iTrade figures go with it).
-- A batch that has a recount batch still needs the recount deleted first.
-- Undo with: STOCK COUNT DELETE POSTED - REVERT.sql (back to: posted batches cannot be deleted)
create or replace function public.sc_delete_batch(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
declare b public.sc_batches;
begin
  select * into b from public.sc_batches where id = p_id;
  if b.id is null then raise exception 'Batch not found.'; end if;
  perform public.require_role(array['ADMIN'], b.branch_id);
  if exists (select 1 from public.sc_batches where parent_id = p_id) then raise exception 'This batch has a recount batch. Delete the recount first.'; end if;
  delete from public.sc_lines where batch_id = p_id;
  delete from public.sc_system where batch_id = p_id;
  delete from public.sc_batches where id = p_id;
end $$;
grant execute on function public.sc_delete_batch(bigint) to authenticated;
select 'sc_delete_batch: posted batches can be deleted by admin' as result;
