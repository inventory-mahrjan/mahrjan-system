-- BACKUP FULL - REVERT.sql
drop function if exists public.backup_table(text, int, int);
drop function if exists public.backup_tables();
drop function if exists public.backup_allowed();
