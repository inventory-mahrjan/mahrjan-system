-- BARCODE FROM STOCK REPORT - REVERT.sql
-- Puts back the barcodes and iTrade codes saved by BARCODE FROM STOCK REPORT - CREATE.sql.
update public.items i set barcode = b.barcode, itrade_code = b.itrade_code, updated_at = now()
from public.item_barcode_backup b where b.item_id = i.id;
update public.stock_report_lines set item_id = null where item_no = '1037' and item_id = 68;
drop table if exists public.item_barcode_backup;
