-- ITEM MASTER SHEET UPDATE - REVERT.sql
-- Puts back pcs_per_box saved by ITEM MASTER SHEET UPDATE - CREATE.sql.
update public.items i set pcs_per_box = b.pcs_per_box, updated_at = now() from public.item_sheet_backup b where b.item_id = i.id;
drop table if exists public.item_sheet_backup;
