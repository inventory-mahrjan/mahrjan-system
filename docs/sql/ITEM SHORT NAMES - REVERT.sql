-- ITEM SHORT NAMES - REVERT.sql
-- Puts back the short names saved by ITEM SHORT NAMES - CREATE.sql.
update public.items i set short_name = b.short_name, updated_at = now() from public.item_short_name_backup b where b.item_id = i.id;
drop table if exists public.item_short_name_backup;
