-- ITEMS FROM STOCK REPORT - REVERT.sql (only while nothing uses them)
delete from public.items where barcode in ('6299001966687','6299003948898','100076990774','6294455889706');
