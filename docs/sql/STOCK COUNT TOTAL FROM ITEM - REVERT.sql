-- STOCK COUNT TOTAL FROM ITEM - REVERT.sql
drop trigger if exists trg_sc_lines_total on public.sc_lines;
drop function if exists public.sc_lines_total();
update public.sc_lines l set total_qty = b.total_qty from public.sc_total_backup b where b.line_id = l.id;
