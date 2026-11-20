-- =====================================================================
-- MAHRJAN SYSTEM - STOCK COUNT (CREATE)
-- Daily / weekly count by the receiver of all stock in the store: finished goods (packs),
-- raw egg and packing material (pieces), good and damage separately. Vans are not counted.
-- Weekly counts can be compared with the iTrade stock (uploaded in the portal).
-- =====================================================================
begin;

create table public.stock_counts (
  id          bigint generated always as identity primary key,
  branch_id   bigint not null references public.branches(id),
  count_date  date not null,
  count_type  text not null check (count_type in ('DAILY','WEEKLY')),
  counted_by  bigint not null references public.staff(id),
  posted_at   timestamptz not null default now(),
  system_loaded_at timestamptz,          -- when the iTrade stock was uploaded (weekly compare)
  created_by  uuid default auth.uid(),
  updated_at  timestamptz,
  updated_by  uuid,
  unique (branch_id, count_date, count_type)
);

create table public.stock_count_lines (
  id          bigint generated always as identity primary key,
  count_id    bigint not null references public.stock_counts(id) on delete cascade,
  item_id     bigint not null references public.items(id),
  good        numeric(12,2) not null default 0 check (good >= 0),
  damage      numeric(12,2) not null default 0 check (damage >= 0),
  system_qty  numeric(12,2),             -- iTrade stock, for the weekly compare
  unique (count_id, item_id)
);

create trigger trg_stock_counts_upd before update on public.stock_counts for each row execute function public.set_updated();
create trigger trg_stock_counts_audit after insert or update or delete on public.stock_counts for each row execute function public.audit_row();
alter table public.stock_counts enable row level security;
alter table public.stock_count_lines enable row level security;
grant select on public.stock_counts, public.stock_count_lines to authenticated;
create policy read_branch on public.stock_counts for select to authenticated
  using (public.can_branch(branch_id) and public.my_role() in ('ADMIN','ACCOUNTANT','RECEIVER','VIEWER'));
create policy read_by_count on public.stock_count_lines for select to authenticated
  using (exists (select 1 from public.stock_counts c where c.id = count_id));

-- SAVE (replaces the lines of that branch / date / type). p_lines = [{"item_id":1,"good":120,"damage":3}, ...]
create or replace function public.save_stock_count(p_branch bigint, p_date date, p_type text, p_lines jsonb)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform public.require_role(array['ADMIN','RECEIVER','ACCOUNTANT'], p_branch);
  if p_type not in ('DAILY','WEEKLY') then raise exception 'Count type must be DAILY or WEEKLY'; end if;
  if public.my_staff_id() is null then raise exception 'Count must be posted by a staff login'; end if;
  insert into public.stock_counts (branch_id, count_date, count_type, counted_by)
  values (p_branch, p_date, p_type, public.my_staff_id())
  on conflict (branch_id, count_date, count_type) do update set counted_by = excluded.counted_by, posted_at = now()
  returning id into v_id;
  delete from public.stock_count_lines where count_id = v_id and system_qty is null;
  insert into public.stock_count_lines (count_id, item_id, good, damage)
  select v_id, (x->>'item_id')::bigint, sum(coalesce((x->>'good')::numeric,0)), sum(coalesce((x->>'damage')::numeric,0))
    from jsonb_array_elements(coalesce(p_lines,'[]')) x
   where coalesce((x->>'good')::numeric,0) + coalesce((x->>'damage')::numeric,0) > 0
   group by (x->>'item_id')::bigint
  on conflict (count_id, item_id) do update set good = excluded.good, damage = excluded.damage;
  update public.stock_count_lines set good = 0, damage = 0
   where count_id = v_id and item_id not in (select (x->>'item_id')::bigint from jsonb_array_elements(coalesce(p_lines,'[]')) x
                                               where coalesce((x->>'good')::numeric,0) + coalesce((x->>'damage')::numeric,0) > 0);
  return v_id;
end $$;

-- iTrade stock for the weekly compare. p_rows = [{"item_code":"6294455889684","qty":540}, ...]  (packs / pieces)
create or replace function public.set_system_stock(p_count bigint, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.stock_counts; v_unknown text;
begin
  select * into c from public.stock_counts where id = p_count;
  if not found then raise exception 'Count not found'; end if;
  perform public.require_role(array['ADMIN','ACCOUNTANT'], c.branch_id);
  update public.stock_count_lines set system_qty = null where count_id = c.id;
  insert into public.stock_count_lines (count_id, item_id, system_qty)
  select c.id, i.id, sum((x->>'qty')::numeric)
    from jsonb_array_elements(p_rows) x join public.items i on i.itrade_code = trim(x->>'item_code')
   group by i.id
  on conflict (count_id, item_id) do update set system_qty = excluded.system_qty;
  select string_agg(distinct trim(x->>'item_code'), ', ') into v_unknown
    from jsonb_array_elements(p_rows) x where not exists (select 1 from public.items i where i.itrade_code = trim(x->>'item_code'));
  update public.stock_counts set system_loaded_at = now() where id = c.id;
  return jsonb_build_object('unknown_items', v_unknown);
end $$;

revoke execute on function public.save_stock_count, public.set_system_stock from public, anon;
grant execute on function public.save_stock_count, public.set_system_stock to authenticated;
commit;
