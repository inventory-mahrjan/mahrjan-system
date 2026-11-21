-- STOCK COUNT RAW EGG BOM - REVERT
do $$ declare d text; begin
  d := pg_get_functiondef('public.sc_download(bigint)'::regprocedure);
  d := replace(d, 'where r.active and ((m.item_type = ''MATERIAL'' and m.material_kind in (''TRAY'',''LABEL'')) or m.item_type = ''RAW_EGG'')',
                  'where r.active and m.item_type = ''MATERIAL'' and m.material_kind in (''TRAY'',''LABEL'')');
  execute d;
end $$;
select 'raw egg BOM removed from download' as result;
