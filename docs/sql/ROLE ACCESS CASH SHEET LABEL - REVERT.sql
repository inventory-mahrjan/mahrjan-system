-- ROLE ACCESS CASH SHEET LABEL - REVERT.sql
update public.role_modules set label = 'Petty cash', grp = 'Reports' where module = 'pc';
