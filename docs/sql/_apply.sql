create or replace function public.mail_data(p_report text, p_from date, p_to date default null)
returns jsonb language plpgsql stable security invoker set search_path = public as $$
declare
  rep text := upper(p_report); t date := coalesce(p_to, p_from); b record;
  units jsonb := '[]'; sec jsonb; secs jsonb; note text; v_sum jsonb;
  g1 numeric := 0; g2 numeric := 0; g3 numeric := 0; g4 numeric := 0; g5 numeric := 0;
begin
  if public.my_role() is null then raise exception 'Not logged in'; end if;
  for b in select id, name from public.branches where public.can_branch(id) order by id loop
    secs := '[]'; note := null;

    if rep in ('VAN_LOAD','SALES_QTY','QTY_MTD') then
      -- item x salesman pivot
      with q as (
        select s.name sm, l.item_id, sum(l.qty) qty, min(d.load_time) lt
          from public.loading_lines l join public.van_day d on d.id = l.van_day_id join public.staff s on s.id = d.salesman_id
         where rep = 'VAN_LOAD' and d.branch_id = b.id and d.business_date = p_from group by 1,2
        union all
        select s.name, l.item_id, sum(l.qty_base), null
          from public.sales_lines l join public.staff s on s.id = l.salesman_id
         where rep <> 'VAN_LOAD' and l.branch_id = b.id and l.tran_date between p_from and t and not l.cancelled and l.item_id is not null group by 1,2),
      men as (select sm, min(lt) lt, row_number() over (order by sm) o from q group by sm),
      its as (select i.id, coalesce(i.short_name, i.name) nm, i.segment, i.display_order,
                     case when i.item_type = 'RAW_EGG' then coalesce(i.pcs_per_carton,1) else coalesce(i.packs_per_carton,1) end per
                from public.items i where i.active and i.item_type <> 'MATERIAL'
                  and (rep = 'VAN_LOAD' or i.id in (select item_id from q)))
      select jsonb_build_object('heading', case rep when 'VAN_LOAD' then 'Boarded qty' else 'Net sales qty (sales less GRV)' end,
        'columns', jsonb_build_array('Item') || coalesce((select jsonb_agg(sm order by o) from men), '[]') || jsonb_build_array('Total', 'Total ctn'),
        'num_from', 1,
        'rows', (case when rep = 'VAN_LOAD' then jsonb_build_array(jsonb_build_array('Load time') || coalesce((select jsonb_agg(coalesce(to_char(lt,'HH24:MI'),'') order by o) from men), '[]') || jsonb_build_array('', '')) else '[]' end)
           || coalesce((select jsonb_agg(jsonb_build_array(case when i.segment = 'OFFER' then i.nm || ' (offer)' else i.nm end)
                 || coalesce((select jsonb_agg(coalesce((select round(q.qty,2) from q where q.sm = m.sm and q.item_id = i.id), 0) order by m.o) from men m), '[]')
                 || jsonb_build_array(coalesce((select round(sum(q.qty),2) from q where q.item_id = i.id), 0),
                                      coalesce((select round(sum(q.qty) / i.per, 2) from q where q.item_id = i.id), 0))
                 order by i.segment, i.display_order nulls last, i.nm) from its i), '[]'),
        'total', jsonb_build_array('Total') || coalesce((select jsonb_agg(coalesce((select round(sum(q.qty),2) from q where q.sm = m.sm),0) order by m.o) from men m), '[]')
                 || jsonb_build_array(coalesce((select round(sum(qty),2) from q),0), coalesce((select round(sum(q.qty / i.per),2) from q join its i on i.id = q.item_id),0)))
        into sec;
      secs := jsonb_build_array(sec);
      g1 := g1 + greatest(jsonb_array_length(sec->'columns') - 3, 0);
      g4 := g4 + coalesce((sec->'total'->>-2)::numeric,0); g5 := g5 + coalesce((sec->'total'->>-1)::numeric,0);
      if rep = 'VAN_LOAD' then
        select string_agg(s.name, ', ' order by s.name) into note from public.staff s
         where s.branch_id = b.id and s.role = 'SALESMAN' and s.active
           and not exists (select 1 from public.van_day d join public.loading_lines l on l.van_day_id = d.id where d.salesman_id = s.id and d.business_date = p_from);
        g2 := g2 + (select count(*) from public.staff s where s.branch_id = b.id and s.role = 'SALESMAN' and s.active);
        note := case when note is null then null else 'Not boarded: ' || note end;
      end if;

    elsif rep = 'DAMAGE' then
      with rate as (select item_id, sum(net) / nullif(sum(qty_base),0) r from public.sales_lines
                     where branch_id = b.id and tran_type = 'CR' and not cancelled and tran_date between p_from - 30 and t group by item_id),
      s as (select salesman_id, sum(net) ex, sum(net_incl_vat) inc from public.sales_lines
             where branch_id = b.id and tran_date between p_from and t and not cancelled and salesman_id is not null group by 1),
      r as (select d.salesman_id, sum(x.damage) dq, sum(x.damage * coalesce(rate.r,0)) dv, sum(x.waste) wq, sum(x.waste * coalesce(rate.r,0)) wv
              from public.return_lines x join public.van_day d on d.id = x.van_day_id left join rate on rate.item_id = x.item_id
             where d.branch_id = b.id and d.business_date between p_from and t group by 1),
      m as (select st.name, coalesce(s.ex,0) ex, coalesce(s.inc,0) inc, coalesce(r.dq,0) dq, coalesce(r.dv,0) dv, coalesce(r.wq,0) wq, coalesce(r.wv,0) wv
              from public.staff st left join s on s.salesman_id = st.id left join r on r.salesman_id = st.id
             where st.branch_id = b.id and (s.salesman_id is not null or r.salesman_id is not null))
      select jsonb_build_object('heading','Salesman-wise sales & damage','num_from',1,
        'columns', jsonb_build_array('Salesman','Sales excl VAT','Sales incl VAT','Damage qty','Damage value','Waste qty','Waste value','Net after damage','Damage %','Waste %'),
        'rows', coalesce(jsonb_agg(jsonb_build_array(name, round(ex,2), round(inc,2), round(dq,2), round(dv,2), round(wq,2), round(wv,2), round(ex-dv,2),
                  case when ex > 0 then round(dv/ex*100,2)::text || '%' else '—' end, case when ex > 0 then round(wv/ex*100,2)::text || '%' else '—' end) order by name), '[]'),
        'total', jsonb_build_array('Total', round(sum(ex),2), round(sum(inc),2), round(sum(dq),2), round(sum(dv),2), round(sum(wq),2), round(sum(wv),2), round(sum(ex-dv),2),
                  case when sum(ex) > 0 then round(sum(dv)/sum(ex)*100,2)::text || '%' else '—' end, case when sum(ex) > 0 then round(sum(wv)/sum(ex)*100,2)::text || '%' else '—' end)),
             coalesce(sum(ex),0), coalesce(sum(dv),0), coalesce(sum(dq),0)
        into sec, g1, g2, g3 from m;
      secs := jsonb_build_array(sec); g4 := g4 + g1; g5 := g5 + g2;

    elsif rep = 'GRV' then
      with gv as (select l.salesman_id, l.item_id, -sum(l.qty_base) grv, -sum(l.net_incl_vat) val from public.sales_lines l
                   where l.branch_id = b.id and l.tran_date between p_from and t and not l.cancelled and l.tran_type <> 'CR' and l.salesman_id is not null group by 1,2),
      rt as (select d.salesman_id, x.item_id, sum(x.damage) dmg, sum(x.waste) wst, sum(x.expiry) exp from public.return_lines x join public.van_day d on d.id = x.van_day_id
              where d.branch_id = b.id and d.business_date between p_from and t group by 1,2),
      k as (select coalesce(gv.salesman_id, rt.salesman_id) sid, coalesce(gv.item_id, rt.item_id) item_id, coalesce(gv.grv,0) grv, coalesce(gv.val,0) val,
                   coalesce(rt.dmg,0) dmg, coalesce(rt.wst,0) wst, coalesce(rt.exp,0) exp
              from gv full join rt on rt.salesman_id = gv.salesman_id and rt.item_id = gv.item_id),
      m as (select st.name, sum(grv) grv, sum(dmg) dmg, sum(wst) wst, sum(exp) exp, sum(val) val from k join public.staff st on st.id = k.sid group by st.name
             having sum(grv) <> 0 or sum(dmg) + sum(wst) + sum(exp) <> 0)
      select jsonb_build_object('heading','GRV vs damage / waste / expiry','num_from',1,
        'columns', jsonb_build_array('Salesman','GRV','Damage','Waste','Expiry','Total D+W+E','Difference','GRV value','Status'),
        'rows', coalesce(jsonb_agg(jsonb_build_array(name, round(grv,2), round(dmg,2), round(wst,2), round(exp,2), round(dmg+wst+exp,2), round(dmg+wst+exp-grv,2), round(val,2),
                  case when dmg+wst+exp = grv then 'Matched' when grv = 0 then 'No GRV' when dmg+wst+exp < grv then 'Short' else 'Excess' end) order by name), '[]'),
        'total', jsonb_build_array('Total', round(sum(grv),2), round(sum(dmg),2), round(sum(wst),2), round(sum(exp),2), round(sum(dmg+wst+exp),2), round(sum(dmg+wst+exp-grv),2), round(sum(val),2),
                  case when count(*) filter (where dmg+wst+exp <> grv) = 0 then 'Matched' else count(*) filter (where dmg+wst+exp <> grv) || ' not matched' end)),
             coalesce(count(*) filter (where dmg+wst+exp <> grv),0)
        into sec, g1 from m;
      g2 := g2 + g1;
      -- item detail where it does not match
      with gv as (select l.salesman_id, l.item_id, -sum(l.qty_base) grv from public.sales_lines l
                   where l.branch_id = b.id and l.tran_date between p_from and t and not l.cancelled and l.tran_type <> 'CR' and l.salesman_id is not null group by 1,2),
      rt as (select d.salesman_id, x.item_id, sum(x.damage) dmg, sum(x.waste) wst, sum(x.expiry) exp from public.return_lines x join public.van_day d on d.id = x.van_day_id
              where d.branch_id = b.id and d.business_date between p_from and t group by 1,2),
      k as (select coalesce(gv.salesman_id, rt.salesman_id) sid, coalesce(gv.item_id, rt.item_id) item_id, coalesce(gv.grv,0) grv,
                   coalesce(rt.dmg,0) dmg, coalesce(rt.wst,0) wst, coalesce(rt.exp,0) exp from gv full join rt on rt.salesman_id = gv.salesman_id and rt.item_id = gv.item_id)
      select secs || jsonb_build_array(jsonb_build_object('heading','Items not matching','num_from',2,
        'columns', jsonb_build_array('Salesman','Item','GRV','Damage','Waste','Expiry','Difference'),
        'rows', coalesce(jsonb_agg(jsonb_build_array(st.name, coalesce(i.short_name, i.name), round(grv,2), round(dmg,2), round(wst,2), round(exp,2), round(dmg+wst+exp-grv,2))
                 order by st.name, i.display_order), '[]')))
        into secs from k join public.staff st on st.id = k.sid join public.items i on i.id = k.item_id where dmg + wst + exp <> grv;
      secs := jsonb_build_array(sec) || secs;

    elsif rep = 'VISIT' then
      with cust as (select a.salesman_id, a.customer_id from public.customer_assignment a join public.customers c on c.id = a.customer_id
                     where a.to_date is null and c.branch_id = b.id and c.active),
      lb as (select customer_id, max(tran_date) last from public.sales_lines where branch_id = b.id and tran_type = 'CR' and not cancelled and tran_date <= t group by 1),
      m as (select st.name, count(*) total,
                   count(*) filter (where lb.last = t) served,
                   count(*) filter (where lb.last between t - 6 and t) d7,
                   count(*) filter (where lb.last between t - 14 and t - 7) d14,
                   count(*) filter (where lb.last between t - 30 and t - 15) d30,
                   count(*) filter (where lb.last is null or lb.last < t - 30) d31
              from cust join public.staff st on st.id = cust.salesman_id left join lb on lb.customer_id = cust.customer_id group by st.name)
      select jsonb_build_object('heading','Customer visit status (by last billed date)','num_from',1,
        'columns', jsonb_build_array('Salesman','Customers','Served today','Billed in last 7 days','8–14 days','15–30 days','Over 30 days / never'),
        'rows', coalesce(jsonb_agg(jsonb_build_array(name, total, served, d7, d14, d30, d31) order by name), '[]'),
        'total', jsonb_build_array('Total', sum(total), sum(served), sum(d7), sum(d14), sum(d30), sum(d31))),
        coalesce(sum(total),0), coalesce(sum(served),0), coalesce(sum(d31),0)
        into sec, g3, g4, g5 from m;
      g1 := g1 + g3; g2 := g2 + g4; g3 := 0; v_sum := coalesce(v_sum, '{}'::jsonb) || jsonb_build_object('b30', coalesce((v_sum->>'b30')::numeric,0) + g5);
      secs := jsonb_build_array(sec);

    elsif rep in ('VARIANCE','FOC','EXPIRY') then
      with rate as (select item_id, sum(net_incl_vat) / nullif(sum(qty_base),0) r from public.sales_lines
                     where branch_id = b.id and tran_type = 'CR' and not cancelled and tran_date between p_from - 30 and t group by item_id),
      x as (select d.business_date dt, st.name sm, coalesce(i.short_name, i.name) item, i.display_order io,
                   case rep when 'FOC' then v.foc when 'EXPIRY' then v.expiry else v.short end q1, case rep when 'VARIANCE' then v.excess else 0 end q2, coalesce(rate.r,0) r
              from public.v_van_day_items v join public.van_day d on d.id = v.van_day_id join public.staff st on st.id = d.salesman_id
              join public.items i on i.id = v.item_id left join rate on rate.item_id = v.item_id
             where d.branch_id = b.id and d.business_date between p_from and t)
      select case when rep = 'VARIANCE' then
          jsonb_build_object('heading','Short & excess by salesman','num_from',1, 'columns', jsonb_build_array('Salesman','Short','Excess','Net (excess − short)','Value AED'),
            'rows', coalesce((select jsonb_agg(jsonb_build_array(sm, round(s1,2), round(s2,2), round(s2-s1,2), round(v,2)) order by sm)
                              from (select sm, sum(q1) s1, sum(q2) s2, sum((q2-q1)*r) v from x group by sm having sum(q1) + sum(q2) <> 0) z), '[]'),
            'total', jsonb_build_array('Total', round(sum(q1),2), round(sum(q2),2), round(sum(q2-q1),2), round(sum((q2-q1)*r),2)))
        else
          jsonb_build_object('heading', case rep when 'FOC' then 'FOC by salesman' else 'Expiry by salesman' end, 'num_from',3, 'columns', jsonb_build_array('Salesman','Date','Item','Qty','Value AED'),
            'rows', coalesce((select jsonb_agg(jsonb_build_array(sm, to_char(dt,'DD-Mon'), item, round(q1,2), round(q1*r,2)) order by sm, dt, io) from x where q1 <> 0), '[]'),
            'total', jsonb_build_array('Total','','', round(sum(q1),2), round(sum(q1*r),2))) end,
        coalesce(sum(q1),0), coalesce(sum(q2),0), coalesce(case when rep = 'VARIANCE' then sum((q2-q1)*r) else sum(q1*r) end,0)
        into sec, g3, g4, g5 from x;
      g1 := g1 + g3; g2 := g2 + g4; v_sum := coalesce(v_sum,'{}'::jsonb) || jsonb_build_object('value', coalesce((v_sum->>'value')::numeric,0) + g5);
      secs := jsonb_build_array(sec);

    elsif rep = 'HEALTH' then
      select jsonb_build_object('heading','Daily check','num_from',99,'columns', jsonb_build_array('Check','Result'),
        'rows', jsonb_agg(jsonb_build_array(k, v) order by o)), count(*) filter (where v <> 'OK')
        into sec, g3 from (
          select 1 o, 'Van days not closed' k, coalesce((select string_agg(s.name || ' (' || d.status || ')', ', ' order by s.name) from public.van_day d join public.staff s on s.id = d.salesman_id
                   where d.branch_id = b.id and d.business_date = p_from and d.status <> 'CLOSED'), 'OK') v
          union all select 2, 'Short / excess', coalesce((select string_agg(s.name || ' short ' || round(sum_s,2) || ' / excess ' || round(sum_e,2), ', ' order by s.name)
                   from (select d.salesman_id, sum(v.short) sum_s, sum(v.excess) sum_e from public.v_van_day_items v join public.van_day d on d.id = v.van_day_id
                          where d.branch_id = b.id and d.business_date = p_from group by 1 having sum(v.short) + sum(v.excess) <> 0) z join public.staff s on s.id = z.salesman_id), 'OK')
          union all select 3, 'Sales without loading', coalesce((select string_agg(distinct s.name, ', ') from public.v_van_day_items v join public.van_day d on d.id = v.van_day_id
                   join public.staff s on s.id = d.salesman_id where d.branch_id = b.id and d.business_date = p_from and v.flag is not null), 'OK')
          union all select 4, 'Cash difference', coalesce((select string_agg(s.name || ' ' || round(d.cash_counted - d.cash_expected,2), ', ' order by s.name) from public.van_day d
                   join public.staff s on s.id = d.salesman_id where d.branch_id = b.id and d.business_date = p_from and d.cash_counted is not null and d.cash_counted <> d.cash_expected), 'OK')
          union all select 5, 'Sales imported', case when exists (select 1 from public.sales_lines where branch_id = b.id and tran_date = p_from and not cancelled) then 'OK' else 'No sales imported for this day' end
          union all select 6, 'Salesman sales with no van day', coalesce((select string_agg(distinct s.name, ', ') from public.sales_lines l join public.staff s on s.id = l.salesman_id
                   where l.branch_id = b.id and l.tran_date = p_from and not l.cancelled and l.van_day_id is null), 'OK')
          union all select 7, 'Item codes not in item master', coalesce((select string_agg(distinct item_code || ' ' || coalesce(item_name,''), ', ') from public.sales_lines
                   where branch_id = b.id and tran_date = p_from and item_id is null and not cancelled), 'OK')
          union all select 8, 'Warehouse batches still open', coalesce((select string_agg(batch_no, ', ' order by batch_no) from public.wh_batches
                   where branch_id = b.id and status = 'ISSUED' and work_date <= p_from), 'OK')
          union all select 9, 'Warehouse egg differences', coalesce((select string_agg(batch_no || ' ' || egg_diff, ', ' order by batch_no) from public.wh_batches
                   where branch_id = b.id and work_date = p_from and status = 'CLOSED' and coalesce(egg_diff,0) <> 0), 'OK')
        ) c;
      g1 := g1 + g3; secs := jsonb_build_array(sec);
    else
      raise exception 'Unknown report %', p_report;
    end if;

    units := units || jsonb_build_array(jsonb_build_object('branch_id', b.id, 'unit', b.name, 'sections', secs, 'note', note));
  end loop;

  return jsonb_build_object('report', rep, 'from', p_from, 'to', t, 'units', units,
    'summary', coalesce(v_sum,'{}'::jsonb) || jsonb_build_object('a', g1, 'b', g2, 'c', g4, 'd', g5));
end $$;