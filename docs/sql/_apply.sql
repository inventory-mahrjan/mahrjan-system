-- STOCK COUNT RAW EGG BOM - CREATE
-- The app's download also carries the raw egg of each finished good (from the BOM), so in the Raw egg
-- category the receiver can scan a finished-good barcode (e.g. KHALEEJ 6) and count its raw egg.
do $$ declare d text; begin
  d := pg_get_functiondef('public.sc_download(bigint)'::regprocedure);
  if position('m.item_type = ''RAW_EGG''' in d) = 0 then
    d := replace(d, 'where r.active and m.item_type = ''MATERIAL'' and m.material_kind in (''TRAY'',''LABEL'')',
                    'where r.active and ((m.item_type = ''MATERIAL'' and m.material_kind in (''TRAY'',''LABEL'')) or m.item_type = ''RAW_EGG'')');
    execute d;
  end if;
end $$;
select case when position('RAW_EGG''))' in pg_get_functiondef('public.sc_download(bigint)'::regprocedure)) > 0 then 'raw egg BOM in download ready' else 'NOT CHANGED' end as result;
