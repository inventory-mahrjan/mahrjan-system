-- MAHRJAN SYSTEM - MIGRATE APP DATA (REVERT): removes the migration functions.
-- The migrated rows stay; to clear them, ask before deleting (this script does not delete data).
begin;
drop function if exists public.migrate_app_data(bigint, date, jsonb);
drop function if exists public.mig_staff(bigint, text);
drop function if exists public.mig_item(text);
commit;
