-- ITEMS FROM STOCK REPORT - CREATE.sql
-- 4 items in the iTrade Stock Report (20 Nov 2026) that were missing in the item master. Copied from a similar item:
--   RM-PLAIN TRAY QUAIL, RM-1X6 TRAY MAHRJAN PREMIUM 6'S BROWN, RM - PLAIN TRAY 15'S  -> trays (material)
--   MAHRJAN ORGANIC EGGS 10'S -> finished goods, 10 per pack, 18 packs per box (no stock now, kept inactive)
-- Undo with: ITEMS FROM STOCK REPORT - REVERT.sql
with src(n, code, name, typ, kind, ppp, ppc, cost, act) as (values
  (1, '6299001966687', 'RM-PLAIN TRAY QUAIL', 'MATERIAL', 'TRAY', null::int, null::int, 0.24, true),
  (2, '6299003948898', 'RM-1X6 TRAY MAHRJAN PREMIUM 6''S BROWN', 'MATERIAL', 'TRAY', null, null, 0.18, true),
  (3, '100076990774', 'RM - PLAIN TRAY 15''S', 'MATERIAL', 'TRAY', null, null, 0.40, true),
  (4, '6294455889706', 'MAHRJAN ORGANIC EGGS 10''S', 'FG', null, 10, 18, null, false)),
base as (select coalesce(max(id), 0) mid, coalesce(max(display_order), 0) mo from public.items),
tpl as (select material_type from public.items where material_kind = 'TRAY' and material_type is not null limit 1)
insert into public.items (barcode, itrade_code, name, item_type, material_kind, material_type, pcs_per_pack, packs_per_carton, unit_cost, active, display_order, segment)
select src.code, src.code, src.name, src.typ, src.kind, case when src.typ = 'MATERIAL' then (select material_type from tpl) end, src.ppp, src.ppc, src.cost, src.act, base.mo + src.n, 'NORMAL'
  from src, base
 where not exists (select 1 from public.items i where i.barcode = src.code or i.itrade_code = src.code);
select string_agg(id || ' ' || name || ' (' || item_type || coalesce('/' || material_kind, '') || ', active ' || active || ')', ' | ') as added
  from public.items where barcode in ('6299001966687','6299003948898','100076990774','6294455889706');
