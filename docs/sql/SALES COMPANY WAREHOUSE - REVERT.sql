-- SALES COMPANY WAREHOUSE - REVERT : import_sales back as before, then the two columns are removed.
do $$
declare d text;
begin
  d := pg_get_functiondef('public.import_sales(bigint,jsonb,boolean)'::regprocedure);
  if position('as company' in d) = 0 then return; end if;
  d := replace(d, ', nullif(trim(x.r->>''Company Name''),'''') as company, nullif(trim(x.r->>''Warehouse''),'''') as warehouse', '');
  d := replace(d, 'net_incl_vat, profit, van_day_id, company, warehouse)', 'net_incl_vat, profit, van_day_id)');
  d := replace(d, ', coalesce(t.company, (select case code when ''MGT'' then ''MAHRJAN GENERAL TRADING LLC-AJMAN'' else ''MAHRJAN GENERAL TRADING LLC-ALQUOZ'' end from public.branches where id = p_branch)), t.warehouse', '');
  d := regexp_replace(d, '\s*/\*CW\*/.*/\*CW-END\*/', '', 's');
  execute d;
end $$;
alter table public.sales_lines drop column if exists warehouse, drop column if exists company;
