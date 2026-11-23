-- BOM PER PACK FIX - REVERT.sql : puts back the BOM and the batch differences saved by BOM PER PACK FIX - CREATE.sql
update public.item_recipe r set qty_per_carton = b.qty_per_carton from public.item_recipe_backup b where b.id = r.id;
update public.wh_lines l set calculated = f.calculated, difference = f.difference, reason = f.reason from public.wh_fix_backup f where f.line_id = l.id;
update public.wh_batches b set egg_diff = f.egg_diff, mat_diff = f.mat_diff from (select distinct batch_id, egg_diff, mat_diff from public.wh_fix_backup) f where f.batch_id = b.id;
