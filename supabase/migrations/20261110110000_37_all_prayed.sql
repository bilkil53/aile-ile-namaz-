-- "5 vaktin hepsini kıldı" aile bildirimi. Kontrol sunucuda yapılır (uygulama bu olayı kendisi
-- gönderemez: pool_events ekleme kuralı ALL_PRAYED'e izin vermez). Kişi ve gün başına BİR kez:
-- işareti kaldırıp yeniden koymak ikinci bildirim göndermez.
alter table public.pool_events drop constraint pool_events_event_type_check;
alter table public.pool_events add constraint pool_events_event_type_check
  check (event_type = any (array['PRAYED','MISSED','KAZA','DUA','MEMBER_JOINED','MEMBER_LEFT','PRO_REQUEST','PRO_DECLINED','ALL_PRAYED']));

-- Hangi gün için bildirildiği (tekrarı önlemek için). Yalnızca son birkaç gün tutulur.
create table if not exists private.all_prayed_log (
  user_id uuid not null references public.profiles(id) on delete cascade,
  prayer_date date not null,
  primary key (user_id, prayer_date)
);
alter table private.all_prayed_log enable row level security;
revoke all on private.all_prayed_log from public, anon, authenticated;

create or replace function private.all_prayed_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
declare today date := (now() at time zone 'Europe/Istanbul')::date;
begin
  -- Yalnızca 5 vaktin hepsi "Kıldı" ise (Muaf günler sayılmaz); eski günler için bildirim yok.
  -- Açık rızası kayıtlı olmayan kişi için aileye bildirim üretilmez (KVKK md. 6, fail-closed).
  if new.fajr = 'PRAYED' and new.dhuhr = 'PRAYED' and new.asr = 'PRAYED'
     and new.maghrib = 'PRAYED' and new.isha = 'PRAYED'
     and new.prayer_date between today - 1 and today + 1
     and exists (select 1 from public.profiles pr where pr.id = new.user_id and pr.acik_riza_at is not null) then
    begin
      insert into private.all_prayed_log(user_id, prayer_date) values (new.user_id, new.prayer_date)
        on conflict do nothing;
      if found then
        insert into public.pool_events(pool_id, sender_id, event_type)
          select m.pool_id, new.user_id, 'ALL_PRAYED' from public.pool_members m where m.user_id = new.user_id;
      end if;
    exception when others then
      -- Bildirim oluşturulamasa bile namaz kaydı başarısız olmasın
      raise warning 'all_prayed: %', sqlerrm;
    end;
  end if;
  return null;
end $$;
revoke all on function private.all_prayed_notify() from public, anon, authenticated;

drop trigger if exists daily_prayers_all_prayed on public.daily_prayers;
create trigger daily_prayers_all_prayed after insert or update on public.daily_prayers
  for each row execute function private.all_prayed_notify();

-- Kurulumdan önce zaten tamamlanmış günler için geç bildirim gitmesin
insert into private.all_prayed_log(user_id, prayer_date)
  select user_id, prayer_date from public.daily_prayers
   where prayer_date >= (now() at time zone 'Europe/Istanbul')::date - 1
     and fajr = 'PRAYED' and dhuhr = 'PRAYED' and asr = 'PRAYED' and maghrib = 'PRAYED' and isha = 'PRAYED'
  on conflict do nothing;

-- Gece temizliği: tekrar önleme kaydı yalnızca 3 gün tutulur (veri en aza)
select cron.unschedule(jobid) from cron.job where jobname = 'aile-cleanup';
select cron.schedule('aile-cleanup', '30 0 * * *', $job$
  delete from public.pool_events where created_at < now() - interval '7 days';
  delete from public.join_requests where status <> 'pending' and created_at < now() - interval '7 days';
  delete from public.join_attempts where attempted_at < now() - interval '1 day';
  delete from private.all_prayed_log where prayer_date < (now() at time zone 'Europe/Istanbul')::date - 3;
$job$);
