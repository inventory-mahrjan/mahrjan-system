-- DELETE LIST APPLY - REVERT.sql
-- Removes the re-check trigger. (Lines it cancelled stay cancelled: their invoices are on the DELETE list.)
drop trigger if exists trg_sales_deletes_apply on public.sales_deletes;
drop function if exists public.sales_deletes_apply();
