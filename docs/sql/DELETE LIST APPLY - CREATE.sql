-- DELETE LIST APPLY - CREATE.sql
-- When an invoice is added to (or removed from) the DELETE list, its sales lines already in the
-- database are re-checked at once (cancelled / restored by trg_sales_lines_deleted).
-- Before this, only sales lines imported after the delete were cancelled.
-- Undo with: DELETE LIST APPLY - REVERT.sql
create or replace function public.sales_deletes_apply() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare v_branch bigint; v_inv text;
begin
  if tg_op = 'DELETE' then v_branch := old.branch_id; v_inv := old.invoice; else v_branch := new.branch_id; v_inv := new.invoice; end if;
  update public.sales_lines s set invoice_no = s.invoice_no
   where s.branch_id = v_branch and public.inv_key(s.invoice_no) = public.inv_key(v_inv);
  return null;
end $$;
drop trigger if exists trg_sales_deletes_apply on public.sales_deletes;
create trigger trg_sales_deletes_apply after insert or delete on public.sales_deletes for each row execute function public.sales_deletes_apply();

-- one-off: re-check November lines whose invoice is on the DELETE list but still counted
with t as (
  update public.sales_lines s set invoice_no = s.invoice_no
   where s.tran_date >= '2026-11-01' and not s.cancelled
     and exists (select 1 from public.sales_deletes d where d.branch_id = s.branch_id and public.inv_key(d.invoice) = public.inv_key(s.invoice_no))
  returning s.invoice_no, s.cancelled)
select count(*) as lines_rechecked, count(*) filter (where cancelled) as now_cancelled, string_agg(distinct invoice_no, ', ') as invoices from t;
