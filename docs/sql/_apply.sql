create or replace function public.migrate_app_data(p_branch bigint, p_from date, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_unknown text; v_items text; n_days int; n jsonb := '{}';
begin
  perform public.require_role(array['ADMIN'], p_branch);
  create temp table if not exists m_names (sm text) on commit drop; truncate m_names;
  insert into m_names select distinct x->>'sm' from jsonb_array_elements(coalesce(p_data->'boards','[]') || coalesce(p_data->'rets','[]') || coalesce(p_data->'vanlog','[]')
        || coalesce(p_data->'exps','[]') || coalesce(p_data->'cols','[]') || coalesce(p_data->'reqs','[]') || coalesce(p_data->'sums','[]')) x
   where (x->>'date')::date >= p_from and coalesce(x->>'sm','') <> '';
  select string_agg(sm, ', ' order by sm) into v_unknown from m_names where public.mig_staff(p_branch, sm) is null;
  if v_unknown is not null then raise exception 'Salesmen not in staff for this branch: % - add them (or their iTrade name) first.', v_unknown; end if;

  -- van days: every salesman-date that has a board, return, van log, expense, collection or summary
  create temp table if not exists m_day (d date, sid bigint, van text) on commit drop; truncate m_day;
  insert into m_day select (x->>'date')::date, public.mig_staff(p_branch, x->>'sm'), max(nullif(x->>'van',''))
    from jsonb_array_elements(coalesce(p_data->'boards','[]') || coalesce(p_data->'rets','[]') || coalesce(p_data->'vanlog','[]')
         || coalesce(p_data->'exps','[]') || coalesce(p_data->'cols','[]') || coalesce(p_data->'sums','[]')) x
   where (x->>'date')::date >= p_from group by 1, 2;
  -- vans used
  insert into public.vans (van_no, branch_id)
  select distinct regexp_replace(van, '\.0$', ''), p_branch from m_day where van ~ '^\d{1,5}(\.0)?$'
     and not exists (select 1 from public.vans v where v.van_no = regexp_replace(m_day.van, '\.0$', ''));

  -- clear those days first (re-run safe)
  delete from public.loading_lines where van_day_id in (select v.id from public.van_day v join m_day m on m.sid = v.salesman_id and m.d = v.business_date);
  delete from public.return_lines  where van_day_id in (select v.id from public.van_day v join m_day m on m.sid = v.salesman_id and m.d = v.business_date);
  delete from public.expenses      where van_day_id in (select v.id from public.van_day v join m_day m on m.sid = v.salesman_id and m.d = v.business_date);
  delete from public.collections   where van_day_id in (select v.id from public.van_day v join m_day m on m.sid = v.salesman_id and m.d = v.business_date);

  insert into public.van_day (branch_id, business_date, salesman_id, route_id, status)
  select p_branch, m.d, m.sid,
         (select route_id from public.customer_assignment a where a.salesman_id = m.sid and a.to_date is null and route_id is not null group by route_id order by count(*) desc limit 1),
         'OPEN'
    from m_day m on conflict (salesman_id, business_date) do nothing;
  get diagnostics n_days = row_count;

  -- VAN LOG
  update public.van_day v set van_id = (select id from public.vans where van_no = regexp_replace(x->>'van','\.0$','') limit 1),
         load_time = nullif(x->>'lt','')::time, load_temp = nullif(x->>'ltemp','')::numeric, start_km = nullif(x->>'skm','')::numeric::int,
         unload_time = nullif(x->>'ut','')::time, unload_temp = nullif(x->>'utemp','')::numeric, end_km = greatest(nullif(x->>'ekm','')::numeric::int, nullif(x->>'skm','')::numeric::int)
    from jsonb_array_elements(coalesce(p_data->'vanlog','[]')) x
   where v.branch_id = p_branch and v.business_date = (x->>'date')::date and v.salesman_id = public.mig_staff(p_branch, x->>'sm') and (x->>'date')::date >= p_from;
  update public.van_day v set van_id = coalesce(v.van_id, (select id from public.vans where van_no = regexp_replace(m.van,'\.0$','') limit 1))
    from m_day m where v.salesman_id = m.sid and v.business_date = m.d;

  -- BOARD
  insert into public.loading_lines (van_day_id, item_id, qty)
  select v.id, public.mig_item(x->>'code'), sum((x->>'qty')::numeric)
    from jsonb_array_elements(coalesce(p_data->'boards','[]')) x
    join public.van_day v on v.branch_id = p_branch and v.business_date = (x->>'date')::date and v.salesman_id = public.mig_staff(p_branch, x->>'sm')
   where (x->>'date')::date >= p_from and public.mig_item(x->>'code') is not null and coalesce((x->>'qty')::numeric,0) > 0
   group by 1, 2;
  -- RETURN
  insert into public.return_lines (van_day_id, item_id, good, damage, expiry, waste, foc)
  select v.id, public.mig_item(x->>'code'), sum(coalesce((x->>'good')::numeric,0)), sum(coalesce((x->>'dmg')::numeric,0)), sum(coalesce((x->>'exp')::numeric,0)),
         sum(coalesce((x->>'wst')::numeric,0)), sum(coalesce((x->>'foc')::numeric,0))
    from jsonb_array_elements(coalesce(p_data->'rets','[]')) x
    join public.van_day v on v.branch_id = p_branch and v.business_date = (x->>'date')::date and v.salesman_id = public.mig_staff(p_branch, x->>'sm')
   where (x->>'date')::date >= p_from and public.mig_item(x->>'code') is not null
   group by 1, 2;
  -- status: returned when a return was posted (also the "no item return" marker), else loaded
  update public.van_day v set status = case
           when exists (select 1 from jsonb_array_elements(coalesce(p_data->'rets','[]')) x where (x->>'date')::date = v.business_date and public.mig_staff(p_branch, x->>'sm') = v.salesman_id) then 'RETURNED'
           when exists (select 1 from public.loading_lines l where l.van_day_id = v.id) then 'LOADED' else 'OPEN' end
    from m_day m where v.salesman_id = m.sid and v.business_date = m.d;

  -- EXPENSE (cartons: the count goes on the van day; the carton trigger writes the expense line)
  update public.van_day v set carton_small = z.cs, carton_big = z.cb
    from (select (x->>'date')::date d, public.mig_staff(p_branch, x->>'sm') sid,
                 sum(case when upper(x->>'type') = 'CARTON SMALL' then coalesce(nullif(split_part(x->>'note',' @',1),'')::numeric, (x->>'amount')::numeric / 0.5) end)::int cs,
                 sum(case when upper(x->>'type') = 'CARTON BIG'   then coalesce(nullif(split_part(x->>'note',' @',1),'')::numeric, (x->>'amount')::numeric / 0.25) end)::int cb
            from jsonb_array_elements(coalesce(p_data->'exps','[]')) x where (x->>'date')::date >= p_from group by 1, 2) z
   where v.business_date = z.d and v.salesman_id = z.sid;
  insert into public.expenses (van_day_id, expense_type, amount, customer_id, note)
  select v.id,
         case when upper(trim(x->>'type')) in ('FUEL','PARKING','SHELF RENT','CREDIT NOTE','OTHER') then upper(trim(x->>'type')) else 'OTHER' end,
         (x->>'amount')::numeric,
         (select c.id from public.customers c where c.branch_id = p_branch and (c.itrade_code = nullif(trim(x->>'head'),'') or upper(c.name) = upper(trim(x->>'customer'))) limit 1),
         case when upper(trim(x->>'type')) in ('FUEL','PARKING','SHELF RENT','CREDIT NOTE') then nullif(trim(x->>'note'),'')
              when upper(trim(x->>'type')) = 'OTHER' then coalesce(nullif(trim(x->>'note'),''), 'OTHER')
              else trim(x->>'type') || coalesce(' — ' || nullif(trim(x->>'note'),''), '') end
    from jsonb_array_elements(coalesce(p_data->'exps','[]')) x
    join public.van_day v on v.branch_id = p_branch and v.business_date = (x->>'date')::date and v.salesman_id = public.mig_staff(p_branch, x->>'sm')
   where (x->>'date')::date >= p_from and upper(x->>'type') not like 'CARTON%' and coalesce((x->>'amount')::numeric,0) > 0
     and (upper(trim(x->>'type')) not in ('SHELF RENT','CREDIT NOTE')
          or exists (select 1 from public.customers c where c.branch_id = p_branch and (c.itrade_code = nullif(trim(x->>'head'),'') or upper(c.name) = upper(trim(x->>'customer')))));
  -- shelf rent / credit note without a known customer -> OTHER, so nothing is lost
  insert into public.expenses (van_day_id, expense_type, amount, note)
  select v.id, 'OTHER', (x->>'amount')::numeric, upper(trim(x->>'type')) || ' — ' || coalesce(nullif(trim(x->>'customer'),''), 'customer not found') || coalesce(' — ' || nullif(trim(x->>'note'),''), '')
    from jsonb_array_elements(coalesce(p_data->'exps','[]')) x
    join public.van_day v on v.branch_id = p_branch and v.business_date = (x->>'date')::date and v.salesman_id = public.mig_staff(p_branch, x->>'sm')
   where (x->>'date')::date >= p_from and upper(trim(x->>'type')) in ('SHELF RENT','CREDIT NOTE') and coalesce((x->>'amount')::numeric,0) > 0
     and not exists (select 1 from public.customers c where c.branch_id = p_branch and (c.itrade_code = nullif(trim(x->>'head'),'') or upper(c.name) = upper(trim(x->>'customer'))));

  -- COLLECTION (new customers are added, as the old sheet did)
  insert into public.customers (itrade_code, name, branch_id)
  select distinct on (coalesce(nullif(trim(x->>'head'),''), upper(trim(x->>'customer')))) nullif(trim(x->>'head'),''), trim(x->>'customer'), p_branch
    from jsonb_array_elements(coalesce(p_data->'cols','[]')) x
   where (x->>'date')::date >= p_from and coalesce(trim(x->>'customer'),'') <> ''
     and not exists (select 1 from public.customers c where (c.itrade_code = nullif(trim(x->>'head'),'')) or (c.branch_id = p_branch and upper(c.name) = upper(trim(x->>'customer'))));
  insert into public.collections (van_day_id, receipt_no, invoice_no, customer_id, mode, amount)
  select v.id,
         coalesce(nullif(regexp_replace(trim(x->>'tran'),'\.0$',''),''), 'NA-' || row_number() over ()),
         nullif(regexp_replace(upper(trim(x->>'invoice')),'\.0$',''),''),
         (select c.id from public.customers c where (c.itrade_code = nullif(trim(x->>'head'),'')) or (c.branch_id = p_branch and upper(c.name) = upper(trim(x->>'customer'))) order by (c.branch_id = p_branch) desc limit 1),
         case when upper(x->>'mode') in ('CASH','CHEQUE','TRANSFER') then upper(x->>'mode') else 'CASH' end,
         (x->>'amount')::numeric
    from jsonb_array_elements(coalesce(p_data->'cols','[]')) x
    join public.van_day v on v.branch_id = p_branch and v.business_date = (x->>'date')::date and v.salesman_id = public.mig_staff(p_branch, x->>'sm')
   where (x->>'date')::date >= p_from and coalesce((x->>'amount')::numeric,0) > 0
  on conflict (receipt_no, van_day_id) do update set amount = collections.amount + excluded.amount;

  -- REQUIREMENT (cartons, by required date)
  delete from public.requirement_lines r using (select distinct (x->>'date')::date d, public.mig_staff(p_branch, x->>'sm') sid from jsonb_array_elements(coalesce(p_data->'reqs','[]')) x where (x->>'date')::date >= p_from) z
   where r.required_date = z.d and r.salesman_id = z.sid;
  insert into public.requirement_lines (branch_id, salesman_id, required_date, item_id, qty_cartons)
  select p_branch, public.mig_staff(p_branch, x->>'sm'), (x->>'date')::date, public.mig_item(x->>'code'), sum((x->>'ctn')::numeric)
    from jsonb_array_elements(coalesce(p_data->'reqs','[]')) x
   where (x->>'date')::date >= p_from and public.mig_item(x->>'code') is not null and coalesce((x->>'ctn')::numeric,0) > 0
   group by 1, 2, 3, 4;

  -- SUMMARY
  update public.van_day v set summary = x - 'sm' - 'date'
    from jsonb_array_elements(coalesce(p_data->'sums','[]')) x
   where (x->>'date')::date >= p_from and v.branch_id = p_branch and v.business_date = (x->>'date')::date and v.salesman_id = public.mig_staff(p_branch, x->>'sm');

  -- DELETE list
  insert into public.sales_deletes (branch_id, del_date, invoice, user_name)
  select distinct on (upper(regexp_replace(x->>'invoice','\s+','','g'))) p_branch, (x->>'date')::date, upper(regexp_replace(regexp_replace(x->>'invoice','\.0$',''),'\s+','','g')), nullif(trim(x->>'user'),'')
    from jsonb_array_elements(coalesce(p_data->'dels','[]')) x where coalesce(x->>'invoice','') <> ''
  on conflict (branch_id, invoice) do nothing;

  -- PETTY CASH
  delete from public.petty_cash where branch_id = p_branch and entry_date >= p_from
     and entry_date in (select distinct (x->>'date')::date from jsonb_array_elements(coalesce(p_data->'petty','[]')) x);
  insert into public.petty_cash (branch_id, entry_date, line_no, line_type, ref, party, note, for_date, amount)
  select p_branch, (x->>'date')::date, row_number() over (partition by x->>'date' order by o), upper(trim(x->>'type')),
         nullif(regexp_replace(trim(x->>'ref'),'\.0$',''),''), coalesce(nullif(trim(x->>'party'),''), '-'), nullif(trim(x->>'note'),''), nullif(x->>'forDate','')::date, (x->>'amount')::numeric
    from jsonb_array_elements(coalesce(p_data->'petty','[]')) with ordinality t(x, o)
   where (x->>'date')::date >= p_from and upper(trim(x->>'type')) in ('RECEIPT','PAYMENT','FOOD ALLOWANCE','TRAVEL ALLOWANCE','DEPOSIT','SUSPENSE','SUSPENSE CLEARED')
     and coalesce((x->>'amount')::numeric,0) > 0;

  -- link sales already imported to these days
  update public.sales_lines l set van_day_id = v.id from public.van_day v
   where l.branch_id = p_branch and l.tran_date >= p_from and l.van_day_id is null and v.salesman_id = l.salesman_id and v.business_date = l.tran_date;

  select string_agg(distinct x->>'code', ', ') into v_items
    from jsonb_array_elements(coalesce(p_data->'boards','[]') || coalesce(p_data->'rets','[]')) x where (x->>'date')::date >= p_from and public.mig_item(x->>'code') is null;
  return jsonb_build_object('van_days_new', n_days, 'van_days', (select count(*) from m_day),
    'loading_lines', (select count(*) from public.loading_lines l join public.van_day v on v.id = l.van_day_id where v.branch_id = p_branch and v.business_date >= p_from),
    'return_lines', (select count(*) from public.return_lines l join public.van_day v on v.id = l.van_day_id where v.branch_id = p_branch and v.business_date >= p_from),
    'expenses', (select count(*) from public.expenses l join public.van_day v on v.id = l.van_day_id where v.branch_id = p_branch and v.business_date >= p_from),
    'collections', (select count(*) from public.collections l join public.van_day v on v.id = l.van_day_id where v.branch_id = p_branch and v.business_date >= p_from),
    'requirements', (select count(*) from public.requirement_lines where branch_id = p_branch and required_date >= p_from),
    'deletes', (select count(*) from public.sales_deletes where branch_id = p_branch),
    'petty', (select count(*) from public.petty_cash where branch_id = p_branch and entry_date >= p_from),
    'unknown_item_codes', v_items);
end $$;