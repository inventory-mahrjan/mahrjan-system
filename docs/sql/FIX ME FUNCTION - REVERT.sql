-- FIX ME FUNCTION - REVERT : the earlier me() (only works while staff has its original 14 columns).
create or replace function public.me() returns public.staff
language sql stable security definer set search_path to 'public' as $function$
 select s.* from public.staff s where s.auth_user_id = auth.uid() and s.active and s.can_login union all select null,null,'SYSTEM',null,'ADMIN',null,null,true,null,true,now(),null,null,null where auth.uid() is null and session_user in ('postgres','supabase_admin') limit 1
$function$;
