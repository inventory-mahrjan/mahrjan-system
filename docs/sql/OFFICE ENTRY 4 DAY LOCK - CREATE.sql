-- OFFICE ENTRY 4 DAY LOCK - CREATE
-- Office entry corrections only for today and the 3 days before (4 days); older days: ADMIN only.
do $$ declare d text; begin
  d := pg_get_functiondef('public.office_save(bigint,date,text,jsonb,jsonb)'::regprocedure);
  if position('OFFICE-4DAY' in d) = 0 then
    d := replace(d, '  perform public.require_role(array[''ACCOUNTANT'',''ADMIN''], s.branch_id);',
      '  perform public.require_role(array[''ACCOUNTANT'',''ADMIN''], s.branch_id);
  /*OFFICE-4DAY*/ if public.my_role() <> ''ADMIN'' and p_date < (now() at time zone ''Asia/Dubai'')::date - 3 then
    raise exception ''This day is locked (older than 4 days). Only admin can change it.''; end if;');
    if position('OFFICE-4DAY' in d) = 0 then raise exception 'office_save text not as expected - nothing changed'; end if;
    execute d;
  end if;
end $$;
select 'office entry 4 day lock ready' as result;
