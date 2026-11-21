-- EMAIL DATA FAST - CREATE
-- The weekly / daily-check emails timed out: mail_data ran with the mailer login's row checks on every row.
-- It now runs as the database owner (same as the other mail_* helpers) and itself allows only ADMIN / VIEWER logins.
do $$ declare d text; begin
  d := pg_get_functiondef('public.mail_data(text,date,date)'::regprocedure);
  if position('MAILDATA-GUARD' in d) = 0 then
    d := regexp_replace(d, '\nbegin\n', E'\nbegin\n  /*MAILDATA-GUARD*/ if public.my_role() not in (''ADMIN'',''VIEWER'') then raise exception ''Not allowed''; end if;\n');
    d := replace(d, 'SECURITY INVOKER', 'SECURITY DEFINER');
    if position('SECURITY DEFINER' in d) = 0 then d := replace(d, 'LANGUAGE plpgsql', 'LANGUAGE plpgsql SECURITY DEFINER'); end if;
    execute d;
  end if;
end $$;
select prosecdef as definer, position('MAILDATA-GUARD' in prosrc) > 0 as guarded from pg_proc where oid = 'public.mail_data(text,date,date)'::regprocedure;
