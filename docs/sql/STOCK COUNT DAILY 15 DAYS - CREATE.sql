-- STOCK COUNT DAILY 15 DAYS - CREATE.sql
-- Daily stock count batches are kept for 15 days only (weekly counts are kept).
-- Every time a new batch is created, daily batches with a count date more than 15 days ago
-- (and their recounts, entries and iTrade figures) are deleted.
-- Undo with: STOCK COUNT DAILY 15 DAYS - REVERT.sql (stops the clean-up; deleted batches do not come back)
create or replace function public.sc_purge_daily(p_days int default 15) returns int
language plpgsql security definer set search_path to 'public' as $$
declare n int := 0; cut date := (now() at time zone 'Asia/Dubai')::date - p_days;
begin
  create temp table if not exists _sc_old (id bigint primary key) on commit drop;
  delete from _sc_old;
  insert into _sc_old select id from public.sc_batches where count_type = 'DAILY' and count_date < cut on conflict do nothing;
  loop   -- recounts of an old batch go too (whatever their own date)
    insert into _sc_old select b.id from public.sc_batches b join _sc_old o on o.id = b.parent_id on conflict do nothing;
    exit when not found;
  end loop;
  delete from public.sc_lines where batch_id in (select id from _sc_old);
  delete from public.sc_system where batch_id in (select id from _sc_old);
  loop   -- children first, then parents
    delete from public.sc_batches b where b.id in (select id from _sc_old) and not exists (select 1 from public.sc_batches c where c.parent_id = b.id);
    get diagnostics n = row_count;
    exit when n = 0;
  end loop;
  select count(*) into n from _sc_old;
  return n;
end $$;
revoke all on function public.sc_purge_daily(int) from public, anon, authenticated;

create or replace function public.sc_purge_daily_trg() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin perform public.sc_purge_daily(15); return null; end $$;
drop trigger if exists trg_sc_purge_daily on public.sc_batches;
create trigger trg_sc_purge_daily after insert on public.sc_batches for each statement execute function public.sc_purge_daily_trg();

select public.sc_purge_daily(15) as old_daily_batches_removed_now;
