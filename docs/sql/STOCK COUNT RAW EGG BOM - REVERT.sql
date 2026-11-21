-- STOCK COUNT RAW EGG BOM - REVERT
do $$ declare d text; begin
  d := pg_get_functiondef('public.sc_download(bigint)'::regprocedure);
  d := replace(d, 'where r.active and (m.item_type = ''RAW_EGG'' or (m.item_type = ''MATERIAL'' and m.material_kind in (''TRAY'',''LABEL''))))',
                  'where r.active and m.item_type = ''MATERIAL'' and m.material_kind in (''TRAY'',''LABEL''))');
  execute d;
end $$;
select 'stock count raw egg BOM removed' as result;
