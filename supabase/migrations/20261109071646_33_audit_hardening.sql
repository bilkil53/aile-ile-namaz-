-- 33: Denetim sıkılaştırması (9 Kasım 2026)
-- 1) push-family çağrıları gizli anahtar taşır (anahtar Vault'ta üretilir; repoda/sohbette yoktur)
-- 2) Aynı telefon (fcm_token) tek hesaba bağlıdır: yeni hesap kaydolunca eskisi silinir
-- 3) Hata raporları gerçekten anonim: kimlik sütunu yok, tarih/kimlik istemciden yazılamaz, saatlik üst sınır
-- 4) İç fonksiyon yetkileri sıkılaştırıldı
-- 5) Kullanılmayan sütunlar kaldırıldı (profiles.email, daily_prayers.note, daily_prayers.updated_at)

-- 1) push-family gizli anahtarı
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'push_hook_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'push_hook_secret',
      'push-family sunucu fonksiyonu çağrı anahtarı');
  end if;
end $$;

create or replace function private.push_hook_secret()
returns text language sql stable security definer set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'push_hook_secret' limit 1
$$;
revoke all on function private.push_hook_secret() from public, anon, authenticated;

-- Sunucu fonksiyonu anahtarı service_role ile buradan okur
create or replace function public.push_hook_secret()
returns text language sql stable security definer set search_path = '' as $$
  select private.push_hook_secret()
$$;
revoke all on function public.push_hook_secret() from public, anon, authenticated;
grant execute on function public.push_hook_secret() to service_role;

create or replace function private.notify_push_family()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform net.http_post(
    url := 'https://tgshrnodnhmnofjhzpqp.supabase.co/functions/v1/push-family',
    body := jsonb_build_object('event_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', private.push_hook_secret()),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  -- Bildirim gönderilemese bile olay kaydı başarısız olmasın
  return new;
end;
$$;

create or replace function private.retry_push_events()
returns void language plpgsql security definer set search_path = '' as $$
declare r record; h jsonb := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', private.push_hook_secret());
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
      headers := h,
      timeout_milliseconds := 5000);
  end loop;
end
$$;
revoke all on function private.retry_push_events() from public, anon, authenticated;
revoke all on function private.notify_push_family() from public, anon, authenticated;

-- 2) Aynı telefon tek hesaba bağlı
create or replace function private.devices_one_owner()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.devices where fcm_token = new.fcm_token and user_id <> new.user_id;
  return new;
end;
$$;
revoke all on function private.devices_one_owner() from public, anon, authenticated;
drop trigger if exists devices_one_owner on public.devices;
create trigger devices_one_owner before insert or update of fcm_token, user_id on public.devices
  for each row execute function private.devices_one_owner();
-- Mevcut çift kayıtlar: aynı telefonda yalnızca en son güncellenen hesap kalır
delete from public.devices d using public.devices e
 where d.fcm_token = e.fcm_token and d.user_id <> e.user_id
   and (d.updated_at < e.updated_at or (d.updated_at = e.updated_at and d.user_id < e.user_id));

-- 3) Anonim hata raporları
drop policy if exists crash_reports_insert on public.crash_reports;
alter table public.crash_reports drop column if exists user_id;
revoke insert, update, delete on public.crash_reports from anon, authenticated;
grant insert (app_version, build, os, ram_mb, fatal, error, stack) on public.crash_reports to anon, authenticated;
create policy crash_reports_insert on public.crash_reports for insert to anon, authenticated with check (true);

create or replace function private.crash_reports_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Kötüye kullanıma karşı: saatte en fazla 300 rapor (uygulama oturum başına zaten en fazla 5 gönderir)
  if (select count(*) from public.crash_reports where created_at > now() - interval '1 hour') >= 300 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  new.created_at := now();
  return new;
end;
$$;
revoke all on function private.crash_reports_limit() from public, anon, authenticated;
drop trigger if exists crash_reports_limit on public.crash_reports;
create trigger crash_reports_limit before insert on public.crash_reports
  for each row execute function private.crash_reports_limit();

-- 4) İç fonksiyon yetkileri
alter function private.pool_max_members() set search_path = '';
revoke all on function private.pool_max_members() from public, anon, authenticated;
revoke all on function private.handle_new_user() from public, anon, authenticated;
revoke all on function private.refresh_kaza_summary() from public, anon, authenticated;
revoke all on function private.gen_invite_code() from public, anon, authenticated;

-- 5) Kullanılmayan sütunlar (veri azaltma)
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), split_part(coalesce(new.email, ''), '@', 1)), 60)
  );
  return new;
end;
$$;
revoke all on function private.handle_new_user() from public, anon, authenticated;
alter table public.profiles drop column if exists email;
alter table public.daily_prayers drop column if exists note;
alter table public.daily_prayers drop column if exists updated_at;
