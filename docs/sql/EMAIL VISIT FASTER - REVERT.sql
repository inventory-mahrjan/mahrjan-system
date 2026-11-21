-- EMAIL VISIT FASTER - REVERT
do $$ declare d text; begin
  d := pg_get_functiondef('public.mail_data(text,date,date)'::regprocedure);
  execute replace(d, 'tran_date between t - 31 and t group by 1', 'tran_date <= t group by 1');
end $$;
select 'visit email as before (index kept: it only speeds up reading)' as result;
