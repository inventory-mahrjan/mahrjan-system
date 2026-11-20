-- MAHRJAN SYSTEM - EMAIL REPORTS (REVERT): removes the email recipients, log and report functions
begin;
delete from public.role_access where module = 'mail';
delete from public.role_modules where module = 'mail';
drop function if exists public.mail_data(text, date, date);
drop function if exists public.mail_ready(date);
drop function if exists public.mail_sent(text, text);
drop function if exists public.mail_log(text, text, text, text, text);
drop function if exists public.mail_recipients(text);
drop table if exists public.email_log;
drop table if exists public.email_recipients;
commit;
