-- FG PACKS PER BOX - CREATE.sql
-- Packets per box for finished goods, as given on 23 Nov 2026:
--   6's = 30, 10's = 18, 15's = 12, 20's = 9, 30's = 8 (ROYAL KHALEEJ WHITE EGG (M) 30's = 6), quail 18's = 24.
-- Old values are kept in item_ppc_backup. Undo with: FG PACKS PER BOX - REVERT.sql
create table if not exists public.item_ppc_backup (item_id bigint primary key, packs_per_carton numeric, saved_at timestamptz default now());
alter table public.item_ppc_backup enable row level security;
insert into public.item_ppc_backup (item_id, packs_per_carton)
  select id, packs_per_carton from public.items where item_type = 'FG' on conflict (item_id) do nothing;
update public.items i set packs_per_carton = v.ppc
  from (select id,
          case when name ilike '%QUAIL%' then 24
               when name ilike '%WHITE EGG (M) 30%' then 6
               when pcs_per_pack = 6 then 30 when pcs_per_pack = 10 then 18 when pcs_per_pack = 15 then 12
               when pcs_per_pack = 20 then 9 when pcs_per_pack = 30 then 8 end as ppc
        from public.items where item_type = 'FG') v
 where i.id = v.id and v.ppc is not null and i.packs_per_carton is distinct from v.ppc;
select string_agg(name || ' = ' || packs_per_carton, ' | ' order by display_order) as fg_packs_per_box from public.items where item_type = 'FG';
