-- EMAIL DAILY LAYOUT - CREATE
-- Data for the four daily emails in the same layout as the old Daily Check PDFs:
--   DAMAGE (salesman wise sales & damage + damage by item), GRV (GRV vs damage / waste / expiry, item-wise),
--   SALES_QTY (item × salesman qty grid with loading time), VISIT (summary + one page per salesman).
-- Read by the Mahrjan Mailer (VIEWER login). Runs as owner, allows only ADMIN / VIEWER.
create or replace function public.mail_daily(p_report text, p_date date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare rep text := upper(p_report); d date := p_date; b record; u jsonb; out jsonb := '[]'::jsonb;
begin
  if public.my_role() not in ('ADMIN','VIEWER') then raise exception 'Not allowed'; end if;
  for b in select id, code, case when code = 'MGT' then 'AJMAN' else 'AL QUOZ' end unit from public.branches where active order by case when code = 'MGT' then 2 else 1 end loop
    if rep = 'DAMAGE' then
      with sl as (select s.*, (select st.id from public.staff st where st.id = s.salesman_id and (coalesce(trim(s.itrade_user),'') = '' or upper(trim(s.itrade_user)) in (upper(st.name), upper(coalesce(st.itrade_name,'')), upper(coalesce(st.erp_user,''))))) own_sid from public.sales_lines s where s.branch_id = b.id and s.tran_date = d and not s.cancelled),
      rate as (select item_id, sum(net) / nullif(sum(qty_base),0) r from public.sales_lines
                where branch_id = b.id and tran_type = 'CR' and not cancelled and qty_base > 0 and tran_date between d - 13 and d group by item_id),
      rl as (select vd.salesman_id, r.item_id, sum(r.damage) dq, sum(r.waste) wq from public.return_lines r join public.van_day vd on vd.id = r.van_day_id
              where vd.branch_id = b.id and vd.business_date = d group by 1,2),
      men as (select own_sid salesman_id from sl where own_sid is not null union select salesman_id from public.van_day where branch_id = b.id and business_date = d),
      rows_ as (select m.salesman_id, st.name nm,
                  coalesce((select sum(net) from sl where sl.own_sid = m.salesman_id),0) ex, coalesce((select sum(net_incl_vat) from sl where sl.own_sid = m.salesman_id),0) inc,
                  coalesce((select sum(dq) from rl where rl.salesman_id = m.salesman_id),0) dq, coalesce((select sum(dq * coalesce(rate.r,0)) from rl left join rate using (item_id) where rl.salesman_id = m.salesman_id),0) dv,
                  coalesce((select sum(wq) from rl where rl.salesman_id = m.salesman_id),0) wq, coalesce((select sum(wq * coalesce(rate.r,0)) from rl left join rate using (item_id) where rl.salesman_id = m.salesman_id),0) wv
                 from men m join public.staff st on st.id = m.salesman_id),
      store as (select 'STORE SALE' nm, coalesce(sum(net),0) ex, coalesce(sum(net_incl_vat),0) inc from sl where own_sid is null),
      itm as (select rl.item_id, coalesce(i.barcode, i.itrade_code) code, i.name, i.display_order o, st.name nm, sum(rl.dq) q, sum(rl.dq * coalesce(rate.r,0)) v
                from rl join public.items i on i.id = rl.item_id join public.staff st on st.id = rl.salesman_id left join rate using (item_id) where rl.dq <> 0 group by 1,2,3,4,5)
      select jsonb_build_object('branch_id', b.id, 'unit', b.unit,
        'rows', coalesce((select jsonb_agg(jsonb_build_object('name', nm, 'ex', round(ex,2), 'inc', round(inc,2), 'dq', dq, 'dv', round(dv,2), 'wq', wq, 'wv', round(wv,2)) order by ex desc) from rows_), '[]')
                || (select jsonb_build_array(jsonb_build_object('name', nm, 'ex', round(ex,2), 'inc', round(inc,2), 'dq', 0, 'dv', 0, 'wq', 0, 'wv', 0)) from store),
        'cols', coalesce((select jsonb_agg(nm order by ex desc) from rows_), '[]'),
        'items', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'by', by, 'q', q, 'v', round(v,2)) order by name)
                             from (select code, name, jsonb_object_agg(nm, q) by, sum(q) q, sum(v) v from itm group by code, name) z), '[]'),
        'noRate', coalesce((select jsonb_agg(distinct i.name) from rl join public.items i on i.id = rl.item_id left join rate using (item_id) where rl.dq + rl.wq <> 0 and rate.r is null), '[]'))
        into u;
    elsif rep = 'GRV' then
      with sl0 as (select s.*, (select st.id from public.staff st where st.id = s.salesman_id and (coalesce(trim(s.itrade_user),'') = '' or upper(trim(s.itrade_user)) in (upper(st.name), upper(coalesce(st.itrade_name,'')), upper(coalesce(st.erp_user,''))))) own_sid from public.sales_lines s where s.branch_id = b.id and s.tran_date = d and not s.cancelled and s.tran_type <> 'CR'),
      sl as (select * from sl0 where own_sid is not null),
      g as (select salesman_id, item_id, sum(abs(qty_base)) grv, sum(abs(net_incl_vat)) gv from sl group by 1,2),
      r as (select vd.salesman_id, r.item_id, sum(r.damage) dmg, sum(r.waste) wst, sum(r.expiry) ex from public.return_lines r join public.van_day vd on vd.id = r.van_day_id
             where vd.branch_id = b.id and vd.business_date = d group by 1,2),
      x as (select coalesce(g.salesman_id, r.salesman_id) sid, coalesce(g.item_id, r.item_id) iid, coalesce(g.grv,0) grv, coalesce(g.gv,0) gv, coalesce(r.dmg,0) dmg, coalesce(r.wst,0) wst, coalesce(r.ex,0) ex
              from g full join r on r.salesman_id = g.salesman_id and r.item_id = g.item_id),
      x2 as (select x.*, st.name nm, coalesce(i.barcode, i.itrade_code) code, i.name iname, i.display_order o,
                    (select rt.name from public.van_day vd join public.routes rt on rt.id = vd.route_id where vd.salesman_id = x.sid and vd.business_date = d limit 1) route
               from x join public.staff st on st.id = x.sid join public.items i on i.id = x.iid where x.grv + x.dmg + x.wst + x.ex <> 0)
      select jsonb_build_object('branch_id', b.id, 'unit', b.unit,
        'men', coalesce((select jsonb_agg(jsonb_build_object('name', nm, 'route', route, 'grv', grv, 'dmg', dmg, 'wst', wst, 'exp', ex, 'gv', round(gv,2)) order by nm)
                          from (select nm, max(route) route, sum(grv) grv, sum(dmg) dmg, sum(wst) wst, sum(ex) ex, sum(gv) gv from x2 group by nm) z), '[]'),
        'items', coalesce((select jsonb_agg(jsonb_build_object('sm', nm, 'code', code, 'name', iname, 'grv', grv, 'dmg', dmg, 'wst', wst, 'exp', ex) order by nm, o nulls last, iname) from x2), '[]'))
        into u;
    elsif rep = 'SALES_QTY' then
      with sl0 as (select s.*, (select st.id from public.staff st where st.id = s.salesman_id and (coalesce(trim(s.itrade_user),'') = '' or upper(trim(s.itrade_user)) in (upper(st.name), upper(coalesce(st.itrade_name,'')), upper(coalesce(st.erp_user,''))))) own_sid from public.sales_lines s where s.branch_id = b.id and s.tran_date = d and not s.cancelled),
      sl as (select * from sl0 where own_sid is not null),
      men as (select st.id, st.name nm,
                     (select to_char(vd.load_time, 'HH24:MI') from public.van_day vd where vd.salesman_id = st.id and vd.business_date = d limit 1) lt
                from public.staff st where st.id in (select salesman_id from sl union select salesman_id from public.van_day where branch_id = b.id and business_date = d))
      select jsonb_build_object('branch_id', b.id, 'unit', b.unit,
        'men', coalesce((select jsonb_agg(jsonb_build_object('name', nm, 'load', lt) order by nm) from men), '[]'),
        'qty', coalesce((select jsonb_object_agg(k, q) from (select sl.item_id || '|' || st.name k, sum(sl.qty_base) q
                                                              from sl join public.staff st on st.id = sl.salesman_id group by 1) z), '{}'))
        into u;
    elsif rep = 'VISIT' then
      with cust as (select a.salesman_id, c.id cid, c.itrade_code head, c.name from public.customer_assignment a join public.customers c on c.id = a.customer_id
                     where a.to_date is null and c.branch_id = b.id and c.active),
      s30 as (select customer_id, tran_date, tender_type, salesman_id from public.sales_lines
               where branch_id = b.id and tran_type = 'CR' and not cancelled and tran_date between d - 29 and d),
      lastb as (select customer_id, max(tran_date) last from public.sales_lines where branch_id = b.id and tran_type = 'CR' and not cancelled and tran_date <= d
                 and customer_id in (select cid from cust) group by 1),
      c2 as (select cust.*, lb.last, (select count(distinct tran_date) from s30 where s30.customer_id = cust.cid) visits,
                    (select case when count(distinct upper(tender_type)) > 1 then 'Mixed' when max(upper(tender_type)) like 'CASH%' then 'Cash' when max(tender_type) is null then '' else 'Credit' end
                       from s30 where s30.customer_id = cust.cid) tender
               from cust left join lastb lb on lb.customer_id = cust.cid)
      select jsonb_build_object('branch_id', b.id, 'unit', b.unit,
        'men', coalesce((select jsonb_agg(jsonb_build_object('name', nm, 'wd', (select count(distinct tran_date) from s30 where s30.salesman_id = z.salesman_id),
                   'customers', cs) order by nm)
              from (select c2.salesman_id, st.name nm,
                      jsonb_agg(jsonb_build_object('head', head, 'name', c2.name, 'last', last, 'days', case when last is null then null else d - last end, 'visits', visits, 'tender', tender)
                                order by last nulls first, c2.name) cs
                      from c2 join public.staff st on st.id = c2.salesman_id group by 1,2) z), '[]'))
        into u;
    else raise exception 'Unknown report %', p_report; end if;
    out := out || jsonb_build_array(u);
  end loop;
  return jsonb_build_object('date', d, 'units', out,
    'items', case when rep = 'SALES_QTY' then (select jsonb_agg(jsonb_build_object('id', id, 'name', coalesce(short_name, name), 'ppc', packs_per_carton, 'offer', segment = 'OFFER') order by display_order nulls last, name)
                                               from public.items where item_type = 'FG' and active) end);
end $$;
revoke all on function public.mail_daily(text, date) from public, anon;
grant execute on function public.mail_daily(text, date) to authenticated;
select 'daily email layout data ready' as result;
