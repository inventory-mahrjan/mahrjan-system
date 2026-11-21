-- SALES REPLACE EDITED - REVERT : import_sales skips invoices already imported again (as before).
do $$
declare d text;
begin
  d := pg_get_functiondef('public.import_sales(bigint,jsonb,boolean)'::regprocedure);
  if position('/*RE*/' in d) = 0 then return; end if;
  d := regexp_replace(d, '\n\s*/\*RE\*/.*/\*RE-END\*/', '', 's');
  d := replace(d, ' m record; v_replaced int := 0;', ' m record;');
  d := replace(d, ' ''replaced_invoices'', v_replaced,', '');
  execute d;
end $$;
