-- Sunucu güvenlik ve kural testleri (canlı veritabanında, GERİ ALINARAK çalışır).
-- Çalıştırma: Supabase SQL Editor'e yapıştır ya da execute_sql ile çalıştır.
-- Blok her durumda sonunda hata fırlatır: tüm değişiklikler geri alınır, veri kalmaz.
-- CI: GitHub'da SUPABASE_DB_URL gizli ayarı tanımlıysa her derlemede çalışır; "SONUC: OK" yoksa yayın durur.
--   Mesaj "SONUC: OK" ile başlıyorsa tüm testler geçti.
--   "SONUC: HATA" ile başlıyorsa başarısız testler listelenir.
-- Gereken: en az bir havuz üyesi (pool_members). Erkek üye yoksa o test atlanır.
do $$
declare
  u uuid; p uuid; male uuid;
  fails text := ''; passed int := 0; skipped text := ''; uyari text := '';
  n int;
begin
  select m.user_id, m.pool_id into u, p from public.pool_members m limit 1;
  if u is null then raise exception 'SONUC: HATA test icin havuz uyesi yok'; end if;

  -- 1) Misafir (anon): Pro, test ve iç fonksiyonlar çağrılamaz
  set local role anon;
  begin perform public.test_restart_trial(); fails := fails || 'anon_test_restart_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin perform public.my_pro_status(); fails := fails || 'anon_my_pro_status_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin perform public.request_pro_from_reis(); fails := fails || 'anon_request_pro_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin perform private.retry_push_events(); fails := fails || 'anon_retry_push_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin perform public.push_hook_secret(); fails := fails || 'anon_bildirim_anahtari_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin insert into public.crash_reports(app_version, error) values ('t', 'test'); passed := passed + 1;
  exception when others then fails := fails || 'anon_hata_raporu: ' || sqlerrm || '; '; end;
  begin insert into public.crash_reports(error, created_at) values ('t', now() + interval '1 year');
    fails := fails || 'hata_raporu_tarihi_yazilabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin insert into public.kaza_prayers(user_id, prayer_type, owed_count, completed_count) values (u, 'FAJR', 1, 0);
    fails := fails || 'anon_kaza_yazabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin insert into public.daily_prayers(user_id, prayer_date, fajr) values (u, '2000-01-02', 'PRAYED');
    fails := fails || 'anon_namaz_yazabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  reset role;

  -- Giriş yapmış kullanıcı u olarak
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;

  -- 2) Normal Pro akışı çalışır, iç fonksiyon çağrılamaz
  begin perform public.my_pro_status(); passed := passed + 1;
  exception when others then fails := fails || 'auth_my_pro_status: ' || sqlerrm || '; '; end;
  begin perform private.retry_push_events(); fails := fails || 'auth_retry_push_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin perform public.push_hook_secret(); fails := fails || 'auth_bildirim_anahtari_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  -- Bilinen açık (demo test paneli için bilerek açık): giriş yapmış herkes deneme süresini
  -- sıfırlayıp Pro'yu kaldırabiliyor. Ücretli Pro'dan önce kapatılmalı; her çalışmada uyarı verilir.
  begin perform public.test_restart_trial(); uyari := uyari || 'test_restart_trial giris yapan herkese ACIK; ';
  exception when insufficient_privilege then null; end;
  begin perform public.test_remove_pro(); uyari := uyari || 'test_remove_pro giris yapan herkese ACIK; ';
  exception when insufficient_privilege then null; end;

  -- 3) pool_events: yalnızca izinli 6 sütun; tarih yazılamaz; değiştirme/silme yok
  begin insert into public.pool_events(pool_id, sender_id, event_type, message) values (p, u, 'DUA', 'test');
    passed := passed + 1;
  exception when others then fails := fails || 'pe_insert_6sutun: ' || sqlerrm || '; '; end;
  begin insert into public.pool_events(pool_id, sender_id, event_type, message) values (p, u, 'DUA', 'test2');
    fails := fails || 'dua_hiz_siniri_calismadi; ';
  exception when sqlstate 'P0001' then passed := passed + 1; end;
  begin insert into public.pool_events(pool_id, sender_id, event_type, created_at) values (p, u, 'KAZA', now() - interval '2 days');
    fails := fails || 'pe_created_at_yazilabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin update public.pool_events set message = 'x' where pool_id = p; fails := fails || 'pe_update_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin delete from public.pool_events where pool_id = p; fails := fails || 'pe_delete_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin insert into public.pool_events(pool_id, sender_id, event_type) values (p, u, 'MEMBER_JOINED');
    fails := fails || 'pe_sistem_olayi_yazilabiliyor; ';
  exception when insufficient_privilege or check_violation then passed := passed + 1; end;

  -- 4) Gizlilik: başkasının kaza kayıtları görünmez
  select count(*) into n from public.kaza_prayers where user_id <> u;
  if n <> 0 then fails := fails || 'baskasinin_kazasi_gorunuyor; '; else passed := passed + 1; end if;
  reset role;

  -- 5) Erkek üyede "Muaf" kaydedilmez (NONE'a çevrilir)
  select m.user_id into male from public.pool_members m
   where m.gender = 'm' or (m.gender is null and m.role_title in ('Aile Reisi','Baba','Oğlu','Babası','Dedesi','Damadı'))
   limit 1;
  if male is null then
    skipped := skipped || 'erkek_muaf(erkek uye yok); ';
  else
    perform set_config('request.jwt.claims', json_build_object('sub', male, 'role', 'authenticated')::text, true);
    set local role authenticated;
    insert into public.daily_prayers(user_id, prayer_date, fajr) values (male, '2000-01-01', 'EXCUSED')
      on conflict (user_id, prayer_date) do update set fajr = excluded.fajr;
    if (select fajr from public.daily_prayers where user_id = male and prayer_date = '2000-01-01') <> 'NONE' then
      fails := fails || 'erkek_muaf_kaydedildi; ';
    else passed := passed + 1; end if;
    reset role;
  end if;

  if fails = '' then
    raise exception 'SONUC: OK % test gecti (geri alindi). Atlanan: %. UYARI: %', passed,
      coalesce(nullif(skipped, ''), 'yok'), coalesce(nullif(uyari, ''), 'yok');
  else
    raise exception 'SONUC: HATA % gecti; basarisiz: % Atlanan: %. UYARI: %', passed, fails,
      coalesce(nullif(skipped, ''), 'yok'), coalesce(nullif(uyari, ''), 'yok');
  end if;
end $$;
