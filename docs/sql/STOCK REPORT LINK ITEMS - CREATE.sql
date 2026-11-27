-- STOCK REPORT LINK ITEMS - CREATE
-- Stock report lines that came in before their items were added to the item master (ids 90-93) are linked by barcode.
update public.stock_report_lines l set item_id = i.id
  from public.items i
 where l.item_id is null and i.barcode = l.item_code and i.id in (90, 91, 92, 93);
