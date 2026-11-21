-- EMAIL DATA FAST - REVERT
do $$ declare d text; begin
  d := pg_get_functiondef('public.mail_data(text,date,date)'::regprocedure);
  d := replace(d, E'  /*MAILDATA-GUARD*/ if public.my_role() not in (''ADMIN'',''VIEWER'') then raise exception ''Not allowed''; end if;\n', '');
  d := replace(d, 'SECURITY DEFINER', 'SECURITY INVOKER');
  execute d;
end $$;
select 'mail_data as before' as result;
