-- FG PACKS PER BOX - REVERT.sql
update public.items i set packs_per_carton = b.packs_per_carton from public.item_ppc_backup b where b.item_id = i.id;
