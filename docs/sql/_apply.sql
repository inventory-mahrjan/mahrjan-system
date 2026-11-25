grant select on public.cash_count, public.cash_count_total, public.cash_opening to authenticated;
notify pgrst, 'reload schema';
select 'ok' as result;
