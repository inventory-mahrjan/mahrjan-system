-- BOM PER PACK FIX - CREATE.sql (23 Nov 2026)
-- The BOM stores qty per carton; eggs/material per pack = qty_per_carton / packs_per_carton.
-- When packs per box changed today (e.g. 15's 24 -> 12) the per-pack use doubled, so production returns
-- showed a false egg / material difference. This rescales the BOM to the new packs per box (per pack stays
-- as before) and recalculates the production batches already closed.
-- Old values kept in item_recipe_backup / wh_fix_backup. Undo with: BOM PER PACK FIX - REVERT.sql
create table if not exists public.item_recipe_backup as select id, qty_per_carton, now() saved_at from public.item_recipe where false;
alter table public.item_recipe_backup enable row level security;
insert into public.item_recipe_backup (id, qty_per_carton) select id, qty_per_carton from public.item_recipe
  where not exists (select 1 from public.item_recipe_backup b where b.id = item_recipe.id);
update public.item_recipe r set qty_per_carton = r.qty_per_carton * i.packs_per_carton / k.packs_per_carton
  from public.items i join public.item_ppc_backup k on k.item_id = i.id
 where r.fg_item_id = i.id and k.packs_per_carton > 0 and i.packs_per_carton > 0 and k.packs_per_carton <> i.packs_per_carton
   and r.qty_per_carton = (select b.qty_per_carton from public.item_recipe_backup b where b.id = r.id);

-- recalc closed production batches
create table if not exists public.wh_fix_backup as
  select l.id line_id, l.calculated, l.difference, l.reason, b.id batch_id, b.egg_diff, b.mat_diff from public.wh_lines l join public.wh_batches b on b.id = l.batch_id where false;
alter table public.wh_fix_backup enable row level security;
insert into public.wh_fix_backup select l.id, l.calculated, l.difference, l.reason, b.id, b.egg_diff, b.mat_diff
  from public.wh_lines l join public.wh_batches b on b.id = l.batch_id
 where b.process = 'PRODUCTION' and b.status = 'CLOSED' and l.line_type = 'BALANCE'
   and not exists (select 1 from public.wh_fix_backup f where f.line_id = l.id);
with iss as (select batch_id, item_id, sum(qty) issued from public.wh_lines where slip = 'I1' group by 1,2),
     used as (select f.batch_id, bom.item_id, sum(f.qty * bom.per_pack) used from public.wh_lines f join public.v_fg_bom bom on bom.fg_item_id = f.for_item_id where f.line_type = 'FG' group by 1,2),
     oth as (select batch_id, item_id, sum(qty) q from public.wh_lines where line_type in ('BROKEN','WASTE','MATERIAL WASTE') and slip = 'R1' group by 1,2),
     n as (select l.id, round(iss.issued - coalesce(used.used,0) - coalesce(oth.q,0)) calc, l.qty
             from public.wh_lines l join public.wh_batches b on b.id = l.batch_id and b.process = 'PRODUCTION' and b.status = 'CLOSED'
             join iss on iss.batch_id = l.batch_id and iss.item_id = l.item_id
             left join used on used.batch_id = l.batch_id and used.item_id = l.item_id
             left join oth on oth.batch_id = l.batch_id and oth.item_id = l.item_id
            where l.line_type = 'BALANCE')
update public.wh_lines l set calculated = n.calc, difference = l.qty - n.calc, reason = case when l.qty - n.calc <> 0 then l.reason end
  from n where n.id = l.id and (l.calculated is distinct from n.calc);
update public.wh_batches b set egg_diff = s.ed, mat_diff = s.md
  from (select l.batch_id, sum(case when l.egg_pcs > 0 or i.item_type = 'RAW_EGG' then l.difference else 0 end) ed,
               sum(case when i.item_type <> 'RAW_EGG' then l.difference else 0 end) md
          from public.wh_lines l join public.items i on i.id = l.item_id where l.line_type = 'BALANCE' group by 1) s
 where s.batch_id = b.id and b.process = 'PRODUCTION' and b.status = 'CLOSED';
select string_agg(batch_no || ' egg diff ' || egg_diff || ' mat diff ' || mat_diff, ' | ' order by id) from public.wh_batches where process = 'PRODUCTION' and status = 'CLOSED';
