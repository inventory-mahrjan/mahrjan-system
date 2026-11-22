-- SUPERVISOR WORDING - REVERT.sql
do $$ declare d text; begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'wh_check_duty';
  execute replace(d, 'an active ACCOUNTANT or SUPERVISOR of this branch', 'an active ACCOUNTANT or RECEIVER of this branch');
end $$;
