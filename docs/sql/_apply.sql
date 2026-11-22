-- BACKUP FULL - CREATE.sql
-- Full database backup for the nightly mailer job and the portal "Download database backup" button.
-- backup_tables()                 -> every table in the public schema
-- backup_table(name, offset, n)   -> rows of one table as JSON, a page at a time
-- Only ADMIN and the MAILER login may call them (they read every table, past the access rules).
-- Undo with: BACKUP FULL - REVERT.sql
create or replace function public.backup_allowed() returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce((public.me()).role = 'ADMIN' or upper((public.me()).name) = 'MAILER', false) $$;

create or replace function public.backup_tables() returns text[]
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.backup_allowed() then raise exception 'Only the admin can take a backup.'; end if;
  return (select array_agg(c.relname::text order by c.relname) from pg_class c join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public' and c.relkind = 'r');
end $$;

create or replace function public.backup_table(p_table text, p_offset int default 0, p_limit int default 5000) returns jsonb
language plpgsql stable security definer set search_path to 'public' as $$
declare r jsonb;
begin
  if not public.backup_allowed() then raise exception 'Only the admin can take a backup.'; end if;
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relname = p_table) then
    raise exception 'Unknown table %', p_table; end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (select * from public.%I order by ctid offset %s limit %s) t', p_table, greatest(p_offset, 0), least(greatest(p_limit, 1), 10000)) into r;
  return r;
end $$;

revoke all on function public.backup_allowed(), public.backup_tables(), public.backup_table(text, int, int) from public, anon;
grant execute on function public.backup_allowed(), public.backup_tables(), public.backup_table(text, int, int) to authenticated;
select proname from pg_proc where proname like 'backup_%' order by 1;
