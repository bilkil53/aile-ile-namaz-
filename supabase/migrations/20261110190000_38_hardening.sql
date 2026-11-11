-- 1) "Okudum" beyan tarihi (kvkk_consent_at) sunucu saatiyle yazılır: uygulamanın gönderdiği tarih
--    ne olursa olsun yok sayılır (geriye / ileriye tarih atılamaz). Eski sürümlerle de çalışır.
create or replace function private.profiles_consent_server_time() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.kvkk_consent_at is not null and new.kvkk_consent_at is distinct from old.kvkk_consent_at then
    new.kvkk_consent_at := now();
  end if;
  return new;
end $$;
revoke all on function private.profiles_consent_server_time() from public, anon, authenticated;
drop trigger if exists profiles_consent_server_time on public.profiles;
create trigger profiles_consent_server_time before update on public.profiles
  for each row execute function private.profiles_consent_server_time();

-- 2) Zamanlanmış görev günlüğü 7 gün tutulur (dakikalık görevler günde ~2.900 satır üretiyor)
select cron.unschedule(jobid) from cron.job where jobname = 'aile-cron-log-cleanup';
select cron.schedule('aile-cron-log-cleanup', '50 0 * * *', $job$
  delete from cron.job_run_details where end_time < now() - interval '7 days';
$job$);

-- 3) Eksik indeks (hesap silinirken katılım istekleri taranmasın)
create index if not exists join_requests_user_id_idx on public.join_requests(user_id);
