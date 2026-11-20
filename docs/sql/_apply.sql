-- =====================================================================
-- SALES COMPANY WAREHOUSE - CREATE
-- The Sales Detailed Report now carries "Company Name" and "Warehouse" on each invoice.
-- 1. sales_lines gets two columns: company, warehouse.
-- 2. Old lines get company from their branch (warehouse stays empty until the report is imported again).
-- 3. import_sales stores both columns, and fills them on invoices already imported.
-- Revert: SALES COMPANY WAREHOUSE - REVERT.sql
-- =====================================================================
alter table public.sales_lines add column if not exists company text, add column if not exists warehouse text;

update public.sales_lines sl
   set company = case b.code when 'MGT' then 'MAHRJAN GENERAL TRADING LLC-AJMAN' else 'MAHRJAN GENERAL TRADING LLC-ALQUOZ' end
  from public.branches b
 where b.id = sl.branch_id and sl.company is null;

do $$
declare d text; n text;
begin
  d := pg_get_functiondef('public.import_sales(bigint,jsonb,boolean)'::regprocedure);
  if position('as company' in d) > 0 then raise notice 'import_sales already has company/warehouse'; return; end if;
  n := regexp_replace(d, 'as profit(\s+)from jsonb_array_elements',
        'as profit, nullif(trim(x.r->>''Company Name''),'''') as company, nullif(trim(x.r->>''Warehouse''),'''') as warehouse\1from jsonb_array_elements');
  if n = d then raise exception 'import_sales: t_in select not found'; end if; d := n;
  n := replace(d, 'net_incl_vat, profit, van_day_id)', 'net_incl_vat, profit, van_day_id, company, warehouse)');
  if n = d then raise exception 'import_sales: insert column list not found'; end if; d := n;
  n := replace(d, 't.profit, d.id',
        't.profit, d.id, coalesce(t.company, (select case code when ''MGT'' then ''MAHRJAN GENERAL TRADING LLC-AJMAN'' else ''MAHRJAN GENERAL TRADING LLC-ALQUOZ'' end from public.branches where id = p_branch)), t.warehouse');
  if n = d then raise exception 'import_sales: insert values not found'; end if; d := n;
  n := replace(d, 'select count(*) into v_new from ins;',
        'select count(*) into v_new from ins;
  /*CW*/ update public.sales_lines sl set company = coalesce(t.company, sl.company), warehouse = coalesce(t.warehouse, sl.warehouse)
    from (select distinct on (invoice_no) invoice_no, company, warehouse from t_in order by invoice_no, ord) t
   where sl.invoice_no = t.invoice_no
     and (sl.company is distinct from coalesce(t.company, sl.company) or sl.warehouse is distinct from coalesce(t.warehouse, sl.warehouse)); /*CW-END*/');
  if n = d then raise exception 'import_sales: insert count not found'; end if; d := n;
  execute d;
end $$;

select count(*) filter (where company is not null) as with_company, count(*) filter (where warehouse is not null) as with_warehouse, count(*) as lines
  from public.sales_lines;
