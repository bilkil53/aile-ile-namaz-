select cron.unschedule(jobid) from cron.job where jobname = 'aile-cleanup';
select cron.schedule('aile-cleanup', '30 0 * * *', $job$
  delete from public.pool_events where created_at < now() - interval '7 days';
  delete from public.join_requests where status <> 'pending' and created_at < now() - interval '7 days';
  delete from public.join_attempts where attempted_at < now() - interval '1 day';
$job$);
