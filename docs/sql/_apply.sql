-- ROLE ACCESS CASH SHEET LABEL - CREATE.sql (25 Nov 2026): the old Petty cash module is now the Cash sheet page (Daily flow)
update public.role_modules set label = 'Cash sheet · opening, cash count, cash book', grp = 'Daily flow' where module = 'pc';
select 'ok' as result;
