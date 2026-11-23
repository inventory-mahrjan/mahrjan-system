-- STOCK COUNT TOTAL FROM ITEM - CREATE.sql
-- The total of a raw egg / finished-good count line is always worked out in the database from the item's current sizes:
--   raw egg  = cartons x pcs per carton + trays x pcs per tray + pcs
--   finished = boxes x packets per box + packets
-- (a device that had old box sizes can no longer save a wrong total), and today's lines are recalculated.
-- Undo with: STOCK COUNT TOTAL FROM ITEM - REVERT.sql
create table if not exists public.sc_total_backup (line_id bigint primary key, total_qty numeric, saved_at timestamptz default now());
alter table public.sc_total_backup enable row level security;

create or replace function public.sc_lines_total() returns trigger language plpgsql security definer set search_path to 'public' as $$
declare it public.items;
begin
  if new.category in ('FG', 'RAW') and (coalesce(new.qty_big, 0) > 0 or coalesce(new.qty_tray, 0) > 0) then
    select * into it from public.items where id = new.item_id;
    if found then
      new.total_qty := case when new.category = 'RAW'
        then coalesce(new.qty_big, 0) * coalesce(it.pcs_per_carton, 0) + coalesce(new.qty_tray, 0) * coalesce(it.pcs_per_tray, 0) + coalesce(new.qty_small, 0)
        else coalesce(new.qty_big, 0) * coalesce(it.packs_per_carton, 0) + coalesce(new.qty_small, 0) end;
    end if;
  end if;
  return new;
end $$;
revoke all on function public.sc_lines_total() from public, anon;
drop trigger if exists trg_sc_lines_total on public.sc_lines;
create trigger trg_sc_lines_total before insert or update on public.sc_lines for each row execute function public.sc_lines_total();

-- recalculate the lines of batches counted from 23 Nov 2026 (old totals kept in sc_total_backup)
insert into public.sc_total_backup (line_id, total_qty)
  select l.id, l.total_qty from public.sc_lines l join public.sc_batches b on b.id = l.batch_id
   where b.count_date >= '2026-11-23' and l.category in ('FG', 'RAW') on conflict (line_id) do nothing;
update public.sc_lines l set qty_big = l.qty_big from public.sc_batches b
 where b.id = l.batch_id and b.count_date >= '2026-11-23' and l.category in ('FG', 'RAW') and (l.qty_big > 0 or l.qty_tray > 0);
select string_agg(i.short_name || ': ' || bk.total_qty || ' -> ' || l.total_qty, ' | ') as changed
  from public.sc_lines l join public.sc_total_backup bk on bk.line_id = l.id join public.items i on i.id = l.item_id where bk.total_qty <> l.total_qty;
