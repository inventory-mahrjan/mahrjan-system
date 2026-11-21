-- STOCK COUNT BATCH - REVERT : removes the batch stock count (tables, functions, new item fields).
drop function if exists public.sc_set_system(bigint, jsonb);
drop function if exists public.sc_upload(bigint, jsonb, boolean);
drop function if exists public.sc_download(bigint);
drop function if exists public.sc_cancel_batch(bigint);
drop function if exists public.sc_save_batch(bigint, bigint, date, text, bigint, text[], text, bigint, bigint[]);
drop table if exists public.sc_system;
drop table if exists public.sc_lines;
drop table if exists public.sc_batches;
alter table public.items drop column if exists unit_cost, drop column if exists pcs_per_box, drop column if exists material_kind;
