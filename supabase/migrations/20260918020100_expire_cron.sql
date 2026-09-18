-- F3: agenda expire_check_ins a cada 10 min quando pg_cron existir.
-- No plano Free sem cron: rode a função no SQL editor ou Edge scheduled.

do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule('expire-check-ins');
exception
  when undefined_function then null;
  when undefined_object then null;
  when others then
    raise notice 'pg_cron unschedule skipped: %', sqlerrm;
end;
$$;

do $$
begin
  perform cron.schedule(
    'expire-check-ins',
    '*/10 * * * *',
    $cron$select public.expire_check_ins()$cron$
  );
exception
  when others then
    raise notice 'pg_cron unavailable — schedule expire_check_ins manually: %', sqlerrm;
end;
$$;
