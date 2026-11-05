-- 1) Bildirim kuyruğu: pending → processing → sent / failed (en fazla 3 deneme, 10 dk içinde)
alter table public.pool_events
  add column if not exists push_status text not null default 'pending',
  add column if not exists push_attempts int not null default 0,
  add column if not exists push_claimed_at timestamptz;
update public.pool_events set push_status = 'sent' where push_status = 'pending';  -- geçmiş olaylar tekrar gönderilmesin
create index if not exists pool_events_push_queue on public.pool_events (push_status, created_at)
  where push_status in ('pending', 'failed', 'processing');

-- Edge Function bir olayı atomik olarak sahiplenir (aynı olay iki kez işlenmez)
create or replace function public.claim_push_event(p_id bigint)
returns setof public.pool_events
language sql security definer set search_path to '' as $$
  update public.pool_events
     set push_status = 'processing', push_attempts = push_attempts + 1, push_claimed_at = now()
   where id = p_id and push_status in ('pending', 'failed') and push_attempts < 3
     and created_at > now() - interval '10 minutes'
  returning *;
$$;

-- Sonuç: gönderildi / tekrar denenecek / vazgeçildi
create or replace function public.finish_push_event(p_id bigint, p_ok boolean)
returns void language sql security definer set search_path to '' as $$
  update public.pool_events
     set push_status = case when p_ok then 'sent' when push_attempts >= 3 then 'dead' else 'failed' end,
         pushed_at = case when p_ok then now() else pushed_at end
   where id = p_id;
$$;

revoke all on function public.claim_push_event(bigint) from public, anon, authenticated;
revoke all on function public.finish_push_event(bigint, boolean) from public, anon, authenticated;
grant execute on function public.claim_push_event(bigint) to service_role;
grant execute on function public.finish_push_event(bigint, boolean) to service_role;

-- Her dakika: takılı kalanı serbest bırak, bekleyen/başarısızları yeniden dene
create or replace function private.retry_push_events() returns void
language plpgsql security definer set search_path to '' as $$
declare r record;
begin
  update public.pool_events set push_status = 'failed'
   where push_status = 'processing' and push_claimed_at < now() - interval '2 minutes';
  for r in select id from public.pool_events
            where push_status in ('pending', 'failed') and push_attempts < 3
              and created_at between now() - interval '10 minutes' and now() - interval '30 seconds'
            order by id limit 50 loop
    perform net.http_post(
      url := 'https://tgshrnodnhmnofjhzpqp.supabase.co/functions/v1/push-family',
      body := jsonb_build_object('event_id', r.id),
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 5000);
  end loop;
end $$;
select cron.schedule('aile-push-retry', '* * * * *', 'select private.retry_push_events();');

-- 2) Muaf kuralı: reisin erkek olarak belirlediği kişi "Muaf" kaydedemez (sessizce boşa çevrilir)
create or replace function private.block_male_excused() returns trigger
language plpgsql security definer set search_path to '' as $$
begin
  if exists (select 1 from public.pool_members m where m.user_id = new.user_id
              and (m.gender = 'm' or (m.gender is null and m.role_title in ('Aile Reisi','Baba','Oğlu','Babası','Dedesi','Damadı')))) then
    if new.fajr = 'EXCUSED' then new.fajr := 'NONE'; end if;
    if new.dhuhr = 'EXCUSED' then new.dhuhr := 'NONE'; end if;
    if new.asr = 'EXCUSED' then new.asr := 'NONE'; end if;
    if new.maghrib = 'EXCUSED' then new.maghrib := 'NONE'; end if;
    if new.isha = 'EXCUSED' then new.isha := 'NONE'; end if;
  end if;
  return new;
end $$;
drop trigger if exists daily_prayers_block_male_excused on public.daily_prayers;
create trigger daily_prayers_block_male_excused before insert or update on public.daily_prayers
  for each row execute function private.block_male_excused();

-- 3) Yetki temizliği: API'nin hiç kullanmadığı tablo yetkileri geri alınır
revoke truncate, trigger, references on all tables in schema public from anon, authenticated;
revoke select, update, delete on public.crash_reports from anon, authenticated;
