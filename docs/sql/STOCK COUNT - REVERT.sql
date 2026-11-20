-- MAHRJAN SYSTEM - STOCK COUNT (REVERT)
begin;
drop function if exists public.set_system_stock, public.save_stock_count;
drop table if exists public.stock_count_lines;
drop table if exists public.stock_counts;
commit;
