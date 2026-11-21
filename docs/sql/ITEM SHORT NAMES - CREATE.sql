-- ITEM SHORT NAMES - CREATE.sql
-- Sets items.short_name from the name / short name list (passed in the SQL editor, not kept in this repo).
-- Old short names are kept in item_short_name_backup. Undo with: ITEM SHORT NAMES - REVERT.sql
-- Run 21-Nov-2026: 41 names matched, 13 short names changed (mostly raw eggs), packing materials left as they were.
create table if not exists public.item_short_name_backup (item_id bigint primary key, short_name text, saved_at timestamptz default now());
alter table public.item_short_name_backup enable row level security;
-- with f as (<name, short name list>), m as (<f matched to items by name>)
-- insert into public.item_short_name_backup (item_id, short_name) select i.id, i.short_name from m join public.items i on i.id = m.id where i.short_name is distinct from m.s on conflict (item_id) do nothing;
-- update public.items i set short_name = m.s, updated_at = now() from m where m.id = i.id and i.short_name is distinct from m.s;
