-- =====================================================================
-- SALES REPLACE EDITED - CREATE
-- Sales import: when an invoice that is already in the system comes again with different lines
-- (edited in iTrade: item, qty or amount changed), its old lines are replaced by the lines in the file.
-- Invoices that are the same are skipped as before. The result shows how many invoices were replaced.
-- Revert: SALES REPLACE EDITED - REVERT.sql
-- =====================================================================
do $$
declare d text; n text;
begin
  d := pg_get_functiondef('public.import_sales(bigint,jsonb,boolean)'::regprocedure);
  if position('/*RE*/' in d) > 0 then raise notice 'already installed'; return; end if;
  n := replace(d, 'v_unknown_items text; v_unknown_sm text; m record;', 'v_unknown_items text; v_unknown_sm text; m record; v_replaced int := 0;');
  if n = d then raise exception 'declare not found'; end if; d := n;
  n := regexp_replace(d, '(\n\s*with ins as \(\s*\n\s*insert into public\.sales_lines)',
    E'\n  /*RE*/ with f as (select invoice_no, string_agg(coalesce(item_code,'''') || '':'' || round(coalesce(qty,0),2)::text || '':'' || round(coalesce(net_incl_vat,0),2)::text, '','' order by ord) sig from t_in group by invoice_no),\n'
    || E'       db as (select invoice_no, string_agg(coalesce(item_code,'''') || '':'' || round(coalesce(qty,0),2)::text || '':'' || round(coalesce(net_incl_vat,0),2)::text, '','' order by line_no) sig\n'
    || E'                from public.sales_lines where branch_id = p_branch and invoice_no in (select invoice_no from f) group by invoice_no),\n'
    || E'       ch as (select f.invoice_no from f join db using (invoice_no) where f.sig is distinct from db.sig),\n'
    || E'       del as (delete from public.sales_lines sl using ch where sl.branch_id = p_branch and sl.invoice_no = ch.invoice_no returning sl.invoice_no)\n'
    || E'  select count(distinct invoice_no) into v_replaced from del; /*RE-END*/\n\\1');
  if n = d then raise exception 'insert not found'; end if; d := n;
  n := replace(d, 'return jsonb_build_object(''rows'', v_total, ''new'', v_new,', 'return jsonb_build_object(''rows'', v_total, ''new'', v_new, ''replaced_invoices'', v_replaced,');
  if n = d then raise exception 'return not found'; end if; d := n;
  execute d;
end $$;
