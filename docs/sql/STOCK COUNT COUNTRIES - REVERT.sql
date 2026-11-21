-- STOCK COUNT COUNTRIES - REVERT
do $$ declare d text; begin
  d := pg_get_functiondef('public.sc_download(bigint)'::regprocedure);
  d := replace(d, '''countries'', (select coalesce(jsonb_agg(name order by sort_order, name), ''[]'') from public.sc_countries where active)',
    '''countries'', (select coalesce(jsonb_agg(c order by c), ''[]'') from (select distinct upper(trim(country)) c from public.sc_lines where coalesce(trim(country),'''') <> ''''
                    union select x from unnest(array[''UAE'',''OMAN'',''SAUDI ARABIA'',''INDIA'',''TURKEY'',''UKRAINE'',''PAKISTAN'',''IRAN'',''BRAZIL'']) x) t)');
  execute d;
end $$;
drop table if exists public.sc_countries;
select 'countries list removed' as result;
