-- EMAIL VISIT FASTER - CREATE
-- The visit email timed out: it read every sale ever made to find each customer's last bill.
-- It only needs the last 31 days (older = "over 30 days / never"), so it now reads just those.
do $$ declare d text; begin
  d := pg_get_functiondef('public.mail_data(text,date,date)'::regprocedure);
  if position('tran_date between t - 31 and t group by 1' in d) = 0 then
    d := replace(d, 'where branch_id = b.id and tran_type = ''CR'' and not cancelled and tran_date <= t group by 1',
                    'where branch_id = b.id and tran_type = ''CR'' and not cancelled and tran_date between t - 31 and t group by 1');
    if position('tran_date between t - 31 and t group by 1' in d) = 0 then raise exception 'mail_data text not as expected - nothing changed'; end if;
    execute d;
  end if;
end $$;
create index if not exists sales_lines_branch_date_idx on public.sales_lines (branch_id, tran_date);
select 'visit email faster' as result;
