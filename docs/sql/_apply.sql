grant select on public.cash_opening to authenticated;
notify pgrst, 'reload schema';
select 'ok' as result;
