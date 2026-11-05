-- G1: Kişi başı olay sınırı (bildirim taşmasını önler)
create or replace function private.pool_events_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  n_min int; n_hour int; n_day int; n_same int;
begin
  -- Sistem olayları (katılım/ayrılma) sınırsız
  if new.event_type in ('MEMBER_JOINED', 'MEMBER_LEFT') then
    return new;
  end if;

  select count(*) filter (where created_at > now() - interval '1 minute'),
         count(*) filter (where created_at > now() - interval '1 hour'),
         count(*) filter (where created_at > now() - interval '1 day')
    into n_min, n_hour, n_day
    from public.pool_events
   where sender_id = new.sender_id
     and event_type = new.event_type
     and created_at > now() - interval '1 day';

  if new.event_type = 'DUA' then
    -- Dakikada 1, saatte 3, günde 10 dua
    if n_min >= 1 or n_hour >= 3 or n_day >= 10 then
      raise exception 'rate_limited' using errcode = 'P0001';
    end if;
  elsif new.event_type in ('PRAYED', 'MISSED') then
    -- Aynı vakit için günde en fazla 2 bildirim, saatte 12
    select count(*) into n_same
      from public.pool_events
     where sender_id = new.sender_id
       and event_type in ('PRAYED', 'MISSED')
       and prayer is not distinct from new.prayer
       and created_at > date_trunc('day', now() at time zone 'Europe/Istanbul') at time zone 'Europe/Istanbul';
    if n_same >= 2 or n_hour >= 12 then
      raise exception 'rate_limited' using errcode = 'P0001';
    end if;
  elsif new.event_type = 'KAZA' then
    -- Saatte 10, günde 30 kaza bildirimi
    if n_hour >= 10 or n_day >= 30 then
      raise exception 'rate_limited' using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.pool_events_rate_limit() from public, anon, authenticated;

drop trigger if exists pool_events_rate_limit on public.pool_events;
create trigger pool_events_rate_limit
  before insert on public.pool_events
  for each row execute function private.pool_events_rate_limit();

-- Sınır sorgusu ve temizlik için uygun indeks (kullanılmayan tekli indeksin yerine)
drop index if exists public.pool_events_sender_idx;
create index if not exists pool_events_sender_time_idx on public.pool_events (sender_id, created_at desc);

-- P2: Kullanılmayan indeks
drop index if exists public.join_requests_user_idx;

-- G2: 5 dakikalık kural için kullanılmayan eski fonksiyonlar kaldırılır
-- (onay yalnızca approve_join_with_roles ile; o fonksiyon 5 dakika ve ünvan kontrolü yapar)
drop function if exists public.approve_join(uuid);
drop function if exists public.create_pool(text, text, text);

-- Süresi dolan istekler "expired" olarak işaretlenir (internet kesilse bile 5 dk sonra kendiliğinden düşer)
alter table public.join_requests drop constraint if exists join_requests_status_check;
alter table public.join_requests add constraint join_requests_status_check
  check (status = any (array['pending', 'approved', 'rejected', 'expired']));

-- P1: Zamanlanmış görevler
create extension if not exists pg_cron;

select cron.unschedule(jobid) from cron.job where jobname in ('aile-expire-requests', 'aile-cleanup');

select cron.schedule('aile-expire-requests', '* * * * *', $job$
  update public.join_requests set status = 'expired'
   where status = 'pending' and created_at < now() - interval '5 minutes';
$job$);

-- Her gece 03:30 (UTC 00:30): aile hareketleri 1 hafta tutulur
select cron.schedule('aile-cleanup', '30 0 * * *', $job$
  delete from public.pool_events where created_at < now() - interval '7 days';
  delete from public.join_requests where status <> 'pending' and created_at < now() - interval '7 days';
  delete from public.join_attempts where created_at < now() - interval '1 day';
$job$);
