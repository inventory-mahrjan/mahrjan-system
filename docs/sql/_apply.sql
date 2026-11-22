select p.proname, substring(pg_get_functiondef(p.oid) from '(?i)[^\n]{0,60}receiver[^\n]{0,60}') as txt
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and pg_get_functiondef(p.oid) ~* 'raise[^;]*receiver|''[^'']*receiver[^'']*''' and p.prokind='f';
