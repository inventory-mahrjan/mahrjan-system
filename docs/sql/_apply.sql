-- STOCK COUNT EXPIRY LIST - CREATE.sql (24 Nov 2026)
-- For the app's stock count: countries and expiry dates per raw egg, taken from
--   1) the previous posted stock count of the same company (and its recounts) - finished goods map to their raw egg through the BOM
--   2) raw egg issued to production (wh_lines ISSUE RAW, origin + expiry) from that count date up to this count date (7 days back if no earlier count)
-- Returns [{m: raw egg item id, c: country, d: expiry date or null}]. Read-only. Undo with: STOCK COUNT EXPIRY LIST - REVERT.sql
create or replace function public.sc_expiry_hints(p_id bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b record; p record;
begin
  select * into b from public.sc_batches where id = p_id;
  if b.id is null or my_role() is null or not can_branch(b.branch_id) then return '[]'::jsonb; end if;
  select * into p from public.sc_batches x where x.branch_id = b.branch_id and x.status = 'POSTED' and x.parent_id is null and x.count_date < b.count_date order by x.count_date desc, x.id desc limit 1;
  return coalesce((select jsonb_agg(distinct jsonb_build_object('m', z.m, 'c', z.c, 'd', z.d)) from (
      select case when i.item_type = 'RAW_EGG' then l.item_id else (select v.item_id from public.v_fg_bom v where v.fg_item_id = l.item_id and v.item_type = 'RAW_EGG' limit 1) end m,
             upper(trim(l.country)) c, l.exp_date d
        from public.sc_lines l join public.items i on i.id = l.item_id
       where p.id is not null and l.batch_id in (select id from public.sc_batches where id = p.id or parent_id = p.id)
         and l.category in ('RAW','FG') and nullif(trim(l.country), '') is not null
      union
      select w.item_id, upper(trim(w.origin)), w.exp_date
        from public.wh_lines w join public.wh_batches wb on wb.id = w.batch_id
       where wb.branch_id = b.branch_id and w.line_type = 'ISSUE RAW' and nullif(trim(w.origin), '') is not null
         and wb.work_date between coalesce(p.count_date, b.count_date - 7) and b.count_date) z where z.m is not null), '[]'::jsonb);
end $$;
revoke all on function public.sc_expiry_hints(bigint) from public, anon;
grant execute on function public.sc_expiry_hints(bigint) to authenticated;
select 'ok' as result;
