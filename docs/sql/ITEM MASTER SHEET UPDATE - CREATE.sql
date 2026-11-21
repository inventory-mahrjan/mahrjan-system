-- ITEM MASTER SHEET UPDATE - CREATE.sql
-- Applies the filled Item master Excel (portal export) to public.items.
-- The sheet rows are passed in the SQL editor as a JSON list (not stored in this repo).
-- Changed items' old values are kept in item_sheet_backup. Undo with: ITEM MASTER SHEET UPDATE - REVERT.sql
-- Run 21-Nov-2026: only pcs_per_box differed (20 trays/lids, all blank before).
create table if not exists public.item_sheet_backup as select id as item_id, pcs_per_box, now() as saved_at from public.items where false;
alter table public.item_sheet_backup enable row level security;
-- with f as (select * from jsonb_to_recordset('<sheet rows>'::jsonb) as x(id bigint, pcs_per_box numeric))
-- insert into public.item_sheet_backup (item_id, pcs_per_box, saved_at) select i.id, i.pcs_per_box, now() from public.items i join f on f.id = i.id where i.pcs_per_box is distinct from f.pcs_per_box;
-- update public.items i set pcs_per_box = f.pcs_per_box, updated_at = now() from f where f.id = i.id and i.pcs_per_box is distinct from f.pcs_per_box;
