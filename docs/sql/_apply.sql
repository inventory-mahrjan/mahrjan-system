-- STOCK COUNT RAW EGG BOM - CREATE
-- Raw egg has no barcode of its own: the receiver scans a finished-good barcode (e.g. KHALEEJ 6) and the app
-- finds its raw egg through the BOM. The app's download now carries the raw-egg BOM lines too (before: only tray / label).
do $$ declare d text; begin
  d := pg_get_functiondef('public.sc_download(bigint)'::regprocedure);
  if position('m.item_type = ''RAW_EGG''' in d) = 0 then
    d := replace(d, 'where r.active and m.item_type = ''MATERIAL'' and m.material_kind in (''TRAY'',''LABEL''))',
                    'where r.active and (m.item_type = ''RAW_EGG'' or (m.item_type = ''MATERIAL'' and m.material_kind in (''TRAY'',''LABEL''))))');
    if position('m.item_type = ''RAW_EGG''' in d) = 0 then raise exception 'sc_download text not as expected - nothing changed'; end if;
    execute d;
  end if;
end $$;
select 'stock count raw egg BOM ready' as result;
