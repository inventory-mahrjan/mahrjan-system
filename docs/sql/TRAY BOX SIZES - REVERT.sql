-- TRAY BOX SIZES - REVERT
update public.items set pcs_per_box = null where id in (90, 92);
