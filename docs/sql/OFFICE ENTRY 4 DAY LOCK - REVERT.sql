-- OFFICE ENTRY 4 DAY LOCK - REVERT
do $$ declare d text; begin
  d := pg_get_functiondef('public.office_save(bigint,date,text,jsonb,jsonb)'::regprocedure);
  d := replace(d, '
  /*OFFICE-4DAY*/ if public.my_role() <> ''ADMIN'' and p_date < (now() at time zone ''Asia/Dubai'')::date - 3 then
    raise exception ''This day is locked (older than 4 days). Only admin can change it.''; end if;', '');
  execute d;
end $$;
select 'office entry lock removed' as result;
