-- CHECK ONLY: nothing is kept. Runs as the admin login with Supabase's guard on bare DELETE / UPDATE switched on,
-- creates a daily stock count batch, deletes it, then cancels everything by ending with an error that shows the result.
load 'safeupdate';
do $$ declare r jsonb; d text; begin
  perform set_config('request.jwt.claims', json_build_object('sub', s.auth_user_id::text, 'role', 'authenticated')::text, true)
    from public.staff s where upper(s.name) = 'MUSTHAFFIR' and s.auth_user_id is not null limit 1;
  set local role authenticated;
  r := public.sc_save_batch(null, (select id from public.branches where code = 'MGAZ'), current_date + 1, 'DAILY',
       (select id from public.staff where upper(name) = 'SHAMEEM' limit 1), array['RAW','FG'], 'system check');
  d := coalesce(public.sc_delete_batch((r->>'id')::bigint)::text, 'done');
  raise exception 'CHECK RESULT (rolled back): created % then deleted (%)', r->>'batch_no', d;
end $$;
