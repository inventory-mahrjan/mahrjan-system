-- =====================================================================
-- MAHRJAN SYSTEM - ROLE ACCESS (REVERT)
-- Puts back the fixed role lists exactly as before "ROLE ACCESS - CREATE.sql".
-- =====================================================================
begin;
do $$
declare r record; d text; d2 text;
begin
  for r in select * from (values
    ('post_loading', $a$array['RECEIVER','ACCOUNTANT','ADMIN']$a$, $a$array['M:load']$a$),
    ('post_return', $a$array['RECEIVER','ACCOUNTANT','ADMIN']$a$, $a$array['M:ret']$a$),
    ('save_requirement', $a$array['SALESMAN','RECEIVER','ACCOUNTANT','ADMIN']$a$, $a$array['M:req']$a$),
    ('save_expenses', $a$array['SALESMAN','ACCOUNTANT','ADMIN']$a$, $a$array['M:days']$a$),
    ('save_collections', $a$array['SALESMAN','ACCOUNTANT','ADMIN']$a$, $a$array['M:days']$a$),
    ('import_sales', $a$array['ACCOUNTANT','ADMIN']$a$, $a$array['M:imp']$a$),
    ('settle_day', $a$array['ACCOUNTANT','ADMIN']$a$, $a$array['M:settle']$a$),
    ('close_day', $a$array['ACCOUNTANT','ADMIN']$a$, $a$array['M:close']$a$),
    ('reopen_day', $a$array['ADMIN']$a$, $a$array['M:reopen']$a$),
    ('wh_check_duty', $a$array['ADMIN','RECEIVER','ACCOUNTANT']$a$, $a$array['M:wh']$a$),
    ('wh_cancel', $a$array['ADMIN','ACCOUNTANT','RECEIVER']$a$, $a$array['M:wh']$a$),
    ('save_stock_count', $a$array['ADMIN','RECEIVER','ACCOUNTANT']$a$, $a$array['M:sc']$a$),
    ('set_system_stock', $a$array['ADMIN','ACCOUNTANT']$a$, $a$array['M:itstock']$a$),
    ('save_petty_cash', $a$array['ADMIN','ACCOUNTANT']$a$, $a$array['M:pc']$a$)) v(fn, old, new) loop
    d := pg_get_functiondef(('public.' || r.fn)::regproc);
    d2 := replace(d, r.new, r.old);
    if d2 = d then raise exception 'Access list not found in function % (already changed?)', r.fn; end if;
    execute d2;
  end loop;
end $$;

create or replace function public.require_role(p_roles text[], p_branch bigint default null)
returns void language plpgsql stable as $$
begin
  if public.my_role() is null then raise exception 'Not logged in or user inactive'; end if;
  if not (public.my_role() = any(p_roles)) then
    raise exception 'Role % is not allowed to do this', public.my_role(); end if;
  if p_branch is not null and not public.can_branch(p_branch) then
    raise exception 'No access to this branch'; end if;
end $$;

drop policy if exists read_branch on public.wh_batches;
create policy read_branch on public.wh_batches for select to authenticated
  using (public.can_branch(branch_id) and public.my_role() in ('ADMIN','ACCOUNTANT','RECEIVER','VIEWER'));
drop policy if exists read_branch on public.stock_counts;
create policy read_branch on public.stock_counts for select to authenticated
  using (public.can_branch(branch_id) and public.my_role() in ('ADMIN','ACCOUNTANT','RECEIVER','VIEWER'));
drop policy if exists read_branch on public.petty_cash;
create policy read_branch on public.petty_cash for select to authenticated
  using (public.can_branch(branch_id) and public.my_role() in ('ADMIN','ACCOUNTANT','VIEWER'));

drop function if exists public.save_role_access(jsonb);
drop function if exists public.can_view(text);
drop function if exists public.can_edit(text);
drop table if exists public.role_access;
drop table if exists public.role_modules;
commit;
