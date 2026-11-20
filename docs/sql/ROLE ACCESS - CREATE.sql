-- =====================================================================
-- MAHRJAN SYSTEM - ROLE ACCESS (CREATE)
-- Makes "what each role can see and do" a setting the ADMIN changes in the portal (Admin → Role access).
--   role_modules : the list of pages / actions (fixed list, used for labels and order)
--   role_access  : per role and module: can_view (page shows) / can_edit (can post / change)
-- The database checks role_access on every save, so the portal setting is the real rule.
-- ADMIN always has full access (cannot lock itself out). Branch rules and the salesman
-- "own day only" rule stay as they are.
-- Defaults below = exactly how access worked before this script.
-- Revert: ROLE ACCESS - REVERT.sql
-- =====================================================================
begin;

create table public.role_modules (
  module     text primary key,
  label      text not null,
  grp        text not null,
  has_edit   boolean not null,
  sort       integer not null
);
insert into public.role_modules (module, label, grp, has_edit, sort) values
  ('ov','Overview','Summary',false,0),
  ('dd','Daily dashboard','Summary',false,1),
  ('load','Loading (board)','Daily flow',true,2),
  ('ret','Return','Daily flow',true,3),
  ('days','Van days · expenses & collections','Daily flow',true,4),
  ('settle','Settle van day (cash)','Daily flow',true,5),
  ('close','Close van day','Daily flow',true,6),
  ('reopen','Reopen closed van day','Daily flow',true,7),
  ('wh','Warehouse · production & cleaning','Daily flow',true,8),
  ('ite','I Trade entry','Daily flow',false,9),
  ('sc','Stock count','Daily flow',true,10),
  ('itstock','iTrade stock upload (compare)','Daily flow',true,11),
  ('imp','Sales import','Daily flow',true,12),
  ('req','Requirement','Daily flow',true,13),
  ('ds','Daily sheets','Reports',false,14),
  ('pc','Petty cash','Reports',true,15),
  ('se','Short & excess','Reports',false,16),
  ('wo','FOC & write-offs','Reports',false,17),
  ('qs','Qty by salesman','Reports',false,18),
  ('sa','Sales analysis','Analysis',false,19),
  ('lr','Loading & return','Analysis',false,20),
  ('vl','Van log','Analysis',false,21),
  ('co','Collections','Analysis',false,22),
  ('ex','Expenses','Analysis',false,23),
  ('dc','Data check','Admin',false,24);

create table public.role_access (
  id         bigint generated always as identity unique,   -- for the audit log
  role       text not null check (role in ('ADMIN','ACCOUNTANT','RECEIVER','SALESMAN','VIEWER','PACKER')),
  module     text not null references public.role_modules(module),
  can_view   boolean not null default false,
  can_edit   boolean not null default false,
  updated_at timestamptz,
  updated_by uuid,
  primary key (role, module)
);
insert into public.role_access (role, module, can_view, can_edit) values
  ('ADMIN','ov',true,false),
  ('ADMIN','dd',true,false),
  ('ADMIN','load',true,true),
  ('ADMIN','ret',true,true),
  ('ADMIN','days',true,true),
  ('ADMIN','settle',true,true),
  ('ADMIN','close',true,true),
  ('ADMIN','reopen',true,true),
  ('ADMIN','wh',true,true),
  ('ADMIN','ite',true,false),
  ('ADMIN','sc',true,true),
  ('ADMIN','itstock',true,true),
  ('ADMIN','imp',true,true),
  ('ADMIN','req',true,true),
  ('ADMIN','ds',true,false),
  ('ADMIN','pc',true,true),
  ('ADMIN','se',true,false),
  ('ADMIN','wo',true,false),
  ('ADMIN','qs',true,false),
  ('ADMIN','sa',true,false),
  ('ADMIN','lr',true,false),
  ('ADMIN','vl',true,false),
  ('ADMIN','co',true,false),
  ('ADMIN','ex',true,false),
  ('ADMIN','dc',true,false),
  ('ACCOUNTANT','ov',true,false),
  ('ACCOUNTANT','dd',true,false),
  ('ACCOUNTANT','load',true,true),
  ('ACCOUNTANT','ret',true,true),
  ('ACCOUNTANT','days',true,true),
  ('ACCOUNTANT','settle',true,true),
  ('ACCOUNTANT','close',true,true),
  ('ACCOUNTANT','reopen',false,false),
  ('ACCOUNTANT','wh',true,true),
  ('ACCOUNTANT','ite',true,false),
  ('ACCOUNTANT','sc',true,true),
  ('ACCOUNTANT','itstock',true,true),
  ('ACCOUNTANT','imp',true,true),
  ('ACCOUNTANT','req',true,true),
  ('ACCOUNTANT','ds',true,false),
  ('ACCOUNTANT','pc',true,true),
  ('ACCOUNTANT','se',true,false),
  ('ACCOUNTANT','wo',true,false),
  ('ACCOUNTANT','qs',true,false),
  ('ACCOUNTANT','sa',true,false),
  ('ACCOUNTANT','lr',true,false),
  ('ACCOUNTANT','vl',true,false),
  ('ACCOUNTANT','co',true,false),
  ('ACCOUNTANT','ex',true,false),
  ('ACCOUNTANT','dc',true,false),
  ('RECEIVER','ov',false,false),
  ('RECEIVER','dd',false,false),
  ('RECEIVER','load',true,true),
  ('RECEIVER','ret',true,true),
  ('RECEIVER','days',true,false),
  ('RECEIVER','settle',false,false),
  ('RECEIVER','close',false,false),
  ('RECEIVER','reopen',false,false),
  ('RECEIVER','wh',true,true),
  ('RECEIVER','ite',true,false),
  ('RECEIVER','sc',true,true),
  ('RECEIVER','itstock',false,false),
  ('RECEIVER','imp',false,false),
  ('RECEIVER','req',true,true),
  ('RECEIVER','ds',false,false),
  ('RECEIVER','pc',false,false),
  ('RECEIVER','se',false,false),
  ('RECEIVER','wo',false,false),
  ('RECEIVER','qs',false,false),
  ('RECEIVER','sa',false,false),
  ('RECEIVER','lr',false,false),
  ('RECEIVER','vl',false,false),
  ('RECEIVER','co',false,false),
  ('RECEIVER','ex',false,false),
  ('RECEIVER','dc',false,false),
  ('SALESMAN','ov',false,false),
  ('SALESMAN','dd',false,false),
  ('SALESMAN','load',false,false),
  ('SALESMAN','ret',false,false),
  ('SALESMAN','days',true,true),
  ('SALESMAN','settle',false,false),
  ('SALESMAN','close',false,false),
  ('SALESMAN','reopen',false,false),
  ('SALESMAN','wh',false,false),
  ('SALESMAN','ite',false,false),
  ('SALESMAN','sc',false,false),
  ('SALESMAN','itstock',false,false),
  ('SALESMAN','imp',false,false),
  ('SALESMAN','req',true,true),
  ('SALESMAN','ds',false,false),
  ('SALESMAN','pc',false,false),
  ('SALESMAN','se',false,false),
  ('SALESMAN','wo',false,false),
  ('SALESMAN','qs',false,false),
  ('SALESMAN','sa',false,false),
  ('SALESMAN','lr',false,false),
  ('SALESMAN','vl',false,false),
  ('SALESMAN','co',false,false),
  ('SALESMAN','ex',false,false),
  ('SALESMAN','dc',false,false),
  ('VIEWER','ov',true,false),
  ('VIEWER','dd',true,false),
  ('VIEWER','load',false,false),
  ('VIEWER','ret',false,false),
  ('VIEWER','days',true,false),
  ('VIEWER','settle',false,false),
  ('VIEWER','close',false,false),
  ('VIEWER','reopen',false,false),
  ('VIEWER','wh',true,false),
  ('VIEWER','ite',true,false),
  ('VIEWER','sc',true,false),
  ('VIEWER','itstock',false,false),
  ('VIEWER','imp',false,false),
  ('VIEWER','req',false,false),
  ('VIEWER','ds',true,false),
  ('VIEWER','pc',true,false),
  ('VIEWER','se',true,false),
  ('VIEWER','wo',true,false),
  ('VIEWER','qs',true,false),
  ('VIEWER','sa',true,false),
  ('VIEWER','lr',true,false),
  ('VIEWER','vl',true,false),
  ('VIEWER','co',true,false),
  ('VIEWER','ex',true,false),
  ('VIEWER','dc',true,false),
  ('PACKER','ov',false,false),
  ('PACKER','dd',false,false),
  ('PACKER','load',false,false),
  ('PACKER','ret',false,false),
  ('PACKER','days',false,false),
  ('PACKER','settle',false,false),
  ('PACKER','close',false,false),
  ('PACKER','reopen',false,false),
  ('PACKER','wh',false,false),
  ('PACKER','ite',false,false),
  ('PACKER','sc',false,false),
  ('PACKER','itstock',false,false),
  ('PACKER','imp',false,false),
  ('PACKER','req',false,false),
  ('PACKER','ds',false,false),
  ('PACKER','pc',false,false),
  ('PACKER','se',false,false),
  ('PACKER','wo',false,false),
  ('PACKER','qs',false,false),
  ('PACKER','sa',false,false),
  ('PACKER','lr',false,false),
  ('PACKER','vl',false,false),
  ('PACKER','co',false,false),
  ('PACKER','ex',false,false),
  ('PACKER','dc',false,false);

create trigger trg_role_access_upd before update on public.role_access for each row execute function public.set_updated();
create trigger trg_role_access_audit after insert or update or delete on public.role_access for each row execute function public.audit_row();
alter table public.role_modules enable row level security;
alter table public.role_access enable row level security;
grant select on public.role_modules, public.role_access to authenticated;
create policy read_all on public.role_modules for select to authenticated using (public.my_role() is not null);
create policy read_all on public.role_access  for select to authenticated using (public.my_role() is not null);

create or replace function public.can_view(p_module text) returns boolean language sql stable security definer set search_path = public as $$
  select public.my_role() = 'ADMIN' or exists (select 1 from public.role_access where role = public.my_role() and module = p_module and (can_view or can_edit)) $$;
create or replace function public.can_edit(p_module text) returns boolean language sql stable security definer set search_path = public as $$
  select public.my_role() = 'ADMIN' or exists (select 1 from public.role_access where role = public.my_role() and module = p_module and can_edit) $$;

-- require_role: an entry 'M:<module>' means "allowed if role_access says can_edit"
create or replace function public.require_role(p_roles text[], p_branch bigint default null)
returns void language plpgsql stable as $$
declare v_mod text;
begin
  if public.my_role() is null then raise exception 'Not logged in or user inactive'; end if;
  select substr(r, 3) into v_mod from unnest(p_roles) r where r like 'M:%' limit 1;
  if v_mod is not null then
    if not public.can_edit(v_mod) then
      raise exception 'Role % has no access to: %', public.my_role(), coalesce((select label from public.role_modules where module = v_mod), v_mod); end if;
  elsif not (public.my_role() = any(p_roles)) then
    raise exception 'Role % is not allowed to do this', public.my_role(); end if;
  if p_branch is not null and not public.can_branch(p_branch) then
    raise exception 'No access to this branch'; end if;
end $$;

-- save the settings (ADMIN only). p_rows = [{"role":"RECEIVER","module":"load","can_view":true,"can_edit":true}, ...]
create or replace function public.save_role_access(p_rows jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  perform public.require_role(array['ADMIN']);
  update public.role_access a set can_view = coalesce((x->>'can_view')::boolean, false) or coalesce((x->>'can_edit')::boolean, false),
         can_edit = coalesce((x->>'can_edit')::boolean, false) and (select has_edit from public.role_modules m where m.module = a.module)
    from jsonb_array_elements(p_rows) x
   where a.role = x->>'role' and a.module = x->>'module' and a.role <> 'ADMIN'
     and (a.can_view, a.can_edit) is distinct from (coalesce((x->>'can_view')::boolean, false) or coalesce((x->>'can_edit')::boolean, false),
                                                   coalesce((x->>'can_edit')::boolean, false));
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.can_view, public.can_edit, public.save_role_access from public, anon;
grant execute on function public.can_view, public.can_edit, public.save_role_access to authenticated;

-- read rules that were tied to role names now follow the "view" setting
drop policy read_branch on public.wh_batches;
create policy read_branch on public.wh_batches for select to authenticated
  using (public.can_branch(branch_id) and (public.can_view('wh') or public.can_view('ite')));
drop policy read_branch on public.stock_counts;
create policy read_branch on public.stock_counts for select to authenticated
  using (public.can_branch(branch_id) and public.can_view('sc'));
drop policy read_branch on public.petty_cash;
create policy read_branch on public.petty_cash for select to authenticated
  using (public.can_branch(branch_id) and public.can_view('pc'));

-- posting functions: same code as before (read live from the database), role list replaced by the module
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
    d2 := replace(d, r.old, r.new);
    if d2 = d then raise exception 'Access list not found in function % (already changed?)', r.fn; end if;
    execute d2;
  end loop;
end $$;

commit;
