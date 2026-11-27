-- STOCK REPORT LINK ITEMS - REVERT
update public.stock_report_lines set item_id = null where item_id in (90, 91, 92, 93);
