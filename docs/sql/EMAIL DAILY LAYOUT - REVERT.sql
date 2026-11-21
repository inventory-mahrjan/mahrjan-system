-- EMAIL DAILY LAYOUT - REVERT
drop function if exists public.mail_daily(text, date);
select 'mail_daily removed' as result;
