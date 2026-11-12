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
  -- Olay testleri rızası olan kişiyle yapılır (rızasız kişinin olayları sunucuda düşürülür, değişiklik 44)
  update public.profiles set acik_riza_at = now(), acik_riza_version = private.riza_version() where id = u;

  -- 1) Misafir (anon): Pro, test ve iç fonksiyonlar çağrılamaz
  set local role anon;
  begin perform public.redeem_pro_code('1'); fails := fails || 'anon_pro_kodu_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
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
  -- Test listesinde olmayan kullanıcı: Pro test işlemleri ve Pro kodu reddedilir
  reset role;
  delete from private.pro_testers where user_id = u; -- sonunda geri alınır
  set local role authenticated;
  begin perform public.test_restart_trial(); fails := fails || 'test_restart_trial_listesize_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin perform public.test_remove_pro(); fails := fails || 'test_remove_pro_listesize_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin perform public.expire_pro_test(); fails := fails || 'expire_pro_test_listesize_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin perform public.redeem_pro_code('1'); fails := fails || 'pro_kodu_listesize_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin if public.am_i_pro_tester() then fails := fails || 'am_i_pro_tester_yanlis_true; '; else passed := passed + 1; end if;
  exception when others then fails := fails || 'am_i_pro_tester: ' || sqlerrm || '; '; end;
  -- Test listesindeki kullanıcı: test işlemi çalışır
  reset role;
  insert into private.pro_testers(user_id) values (u);
  set local role authenticated;
  begin perform public.test_remove_pro(); passed := passed + 1;
  exception when others then fails := fails || 'test_remove_pro_listedekine_kapali: ' || sqlerrm || '; '; end;

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
    insert into public.daily_prayers(user_id, prayer_date, fajr) values (male, (now() at time zone 'Europe/Istanbul')::date, 'EXCUSED')
      on conflict (user_id, prayer_date) do update set fajr = excluded.fajr;
    if (select fajr from public.daily_prayers where user_id = male and prayer_date = (now() at time zone 'Europe/Istanbul')::date) <> 'NONE' then
      fails := fails || 'erkek_muaf_kaydedildi; ';
    else passed := passed + 1; end if;
    reset role;
  end if;

  -- 6) Cihaz dili: yalnızca 'tr' / 'en' kaydedilir; verilmezse Türkçe (eski sürümler)
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    insert into public.devices(user_id, fcm_token, platform, lang)
      values (u, 'ci-dil-testi-gecersiz-0000000000000000001', 'android', 'de');
    fails := fails || 'cihaz_dili_gecersiz_kabul; ';
  exception when check_violation then passed := passed + 1;
  end;
  insert into public.devices(user_id, fcm_token, platform)
    values (u, 'ci-dil-testi-varsayilan-00000000000000002', 'android');
  if (select lang from public.devices where fcm_token = 'ci-dil-testi-varsayilan-00000000000000002') is distinct from 'tr' then
    fails := fails || 'cihaz_dili_varsayilan_tr_degil; ';
  else passed := passed + 1; end if;

  -- 7) Açık rıza tarihi: yalnızca sunucu saatiyle, yalnızca kendi kaydına yazılır; elle tarih yazılamaz
  begin
    if public.record_acik_riza() between now() - interval '1 minute' and now() + interval '1 minute'
    then passed := passed + 1; else fails := fails || 'acik_riza_tarihi_yanlis; '; end if;
  exception when others then fails := fails || 'acik_riza_kaydi: ' || sqlerrm || '; '; end;
  begin update public.profiles set acik_riza_at = '2000-01-01' where id = u;
    fails := fails || 'acik_riza_elle_yazilabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  -- "Okudum" beyan tarihi de sunucu saatiyle yazılır (gönderilen tarih yok sayılır)
  update public.profiles set kvkk_consent_at = '2000-01-01' where id = u;
  reset role;
  if (select kvkk_consent_at from public.profiles where id = u) between now() - interval '1 minute' and now() + interval '1 minute'
  then passed := passed + 1; else fails := fails || 'beyan_tarihi_elle_yazilabiliyor; '; end if;
  set local role authenticated;
  begin perform acik_riza_at from public.profiles where id = u; -- rıza tarihi aileye/API'ye görünmez
    fails := fails || 'acik_riza_okunabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  reset role;
  set local role anon;
  begin perform public.record_acik_riza(); fails := fails || 'anon_acik_riza_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  reset role;

  -- 8) "5 vaktin hepsini kıldı": sunucu gün başına bir kez aile olayı üretir; uygulama kendisi gönderemez
  delete from private.all_prayed_log where user_id = u; -- sonunda geri alınır
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin insert into public.pool_events(pool_id, sender_id, event_type) values (p, u, 'ALL_PRAYED');
    fails := fails || 'all_prayed_istemciden_yazilabiliyor; ';
  exception when insufficient_privilege or check_violation then passed := passed + 1; end;
  insert into public.daily_prayers(user_id, prayer_date, fajr, dhuhr, asr, maghrib, isha)
    values (u, (now() at time zone 'Europe/Istanbul')::date, 'PRAYED', 'PRAYED', 'PRAYED', 'PRAYED', 'PRAYED')
    on conflict (user_id, prayer_date) do update
      set fajr = 'PRAYED', dhuhr = 'PRAYED', asr = 'PRAYED', maghrib = 'PRAYED', isha = 'PRAYED';
  select count(*) into n from public.pool_events
   where sender_id = u and event_type = 'ALL_PRAYED' and created_at > now() - interval '1 minute';
  if n < 1 then fails := fails || 'all_prayed_olayi_olusmadi; '; else passed := passed + 1; end if;
  -- İşareti kaldırıp yeniden koymak ikinci bildirim üretmez
  update public.daily_prayers set isha = 'NONE' where user_id = u and prayer_date = (now() at time zone 'Europe/Istanbul')::date;
  update public.daily_prayers set isha = 'PRAYED' where user_id = u and prayer_date = (now() at time zone 'Europe/Istanbul')::date;
  if (select count(*) from public.pool_events where sender_id = u and event_type = 'ALL_PRAYED'
       and created_at > now() - interval '1 minute') <> n then
    fails := fails || 'all_prayed_tekrar_gonderildi; ';
  else passed := passed + 1; end if;
  -- Eski bir gün tamamlanınca bildirim yok
  -- (Geçmiş gün artık yazılamaz; yazılabilseydi de bildirim olmamalı)
  begin
    insert into public.daily_prayers(user_id, prayer_date, fajr, dhuhr, asr, maghrib, isha)
      values (u, '2000-01-03', 'PRAYED', 'PRAYED', 'PRAYED', 'PRAYED', 'PRAYED')
      on conflict (user_id, prayer_date) do update
        set fajr = 'PRAYED', dhuhr = 'PRAYED', asr = 'PRAYED', maghrib = 'PRAYED', isha = 'PRAYED';
    fails := fails || 'gecmis_gun_yazilabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  if (select count(*) from public.pool_events where sender_id = u and event_type = 'ALL_PRAYED'
       and created_at > now() - interval '1 minute') <> n then
    fails := fails || 'all_prayed_eski_gun_bildirildi; ';
  else passed := passed + 1; end if;
  -- Muaf vakti olan gün ve ileri tarih (bugün+2) bildirilmez
  begin
    insert into public.daily_prayers(user_id, prayer_date, fajr, dhuhr, asr, maghrib, isha)
      values (u, (now() at time zone 'Europe/Istanbul')::date + 2, 'PRAYED', 'PRAYED', 'PRAYED', 'PRAYED', 'PRAYED')
      on conflict (user_id, prayer_date) do update
        set fajr = 'PRAYED', dhuhr = 'PRAYED', asr = 'PRAYED', maghrib = 'PRAYED', isha = 'PRAYED';
    fails := fails || 'ileri_tarih_yazilabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  insert into public.daily_prayers(user_id, prayer_date, fajr, dhuhr, asr, maghrib, isha)
    values (u, (now() at time zone 'Europe/Istanbul')::date - 1, 'PRAYED', 'PRAYED', 'EXCUSED', 'PRAYED', 'PRAYED')
    on conflict (user_id, prayer_date) do update
      set fajr = 'PRAYED', dhuhr = 'PRAYED', asr = 'EXCUSED', maghrib = 'PRAYED', isha = 'PRAYED';
  if (select count(*) from public.pool_events where sender_id = u and event_type = 'ALL_PRAYED'
       and created_at > now() - interval '1 minute') <> n then
    fails := fails || 'all_prayed_muaf_ya_da_ileri_tarih_bildirildi; ';
  else passed := passed + 1; end if;
  -- Tekrar önleme kaydı istemciden okunamaz
  begin perform 1 from private.all_prayed_log limit 1; fails := fails || 'all_prayed_kaydi_okunabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  reset role;
  -- Açık rızası kayıtlı değilse aileye bildirim üretilmez
  update public.profiles set acik_riza_at = null where id = u;
  delete from private.all_prayed_log where user_id = u;
  set local role authenticated;
  update public.daily_prayers set isha = 'NONE' where user_id = u and prayer_date = (now() at time zone 'Europe/Istanbul')::date;
  update public.daily_prayers set isha = 'PRAYED' where user_id = u and prayer_date = (now() at time zone 'Europe/Istanbul')::date;
  if (select count(*) from public.pool_events where sender_id = u and event_type = 'ALL_PRAYED'
       and created_at > now() - interval '1 minute') <> n then
    fails := fails || 'all_prayed_rizasiz_bildirildi; ';
  else passed := passed + 1; end if;
  reset role;

  -- 10) Bildirim teslim kaydı (41) ve rıza durumu (41, 42)
  perform set_config('request.jwt.claims', '', true); -- kimliksiz: yalnızca izin hatası kabul edilir
  set local role anon;
  begin perform public.my_consent_status(); fails := fails || 'anon_riza_durumu_acik; ';
  exception when insufficient_privilege then
    if sqlerrm like 'permission denied%' then passed := passed + 1;
    else fails := fails || 'anon_riza_durumu_izin_yerine_fonksiyon_icinde_durdu; '; end if;
  end;
  begin perform public.push_delivered_tokens(0); fails := fails || 'anon_teslim_listesi_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  reset role;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin perform public.push_delivered_tokens(0); fails := fails || 'uye_teslim_listesi_acik; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin perform public.mark_push_delivered(0, array['x']); fails := fails || 'uye_teslim_yazabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin perform 1 from private.push_deliveries limit 1; fails := fails || 'teslim_tablosu_okunabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  begin update public.profiles set acik_riza_version = 99 where id = u; fails := fails || 'riza_surumu_yazilabiliyor; ';
  exception when insufficient_privilege then passed := passed + 1; end;
  -- Bölüm 7'de beyan tarihi yazıldı, bölüm 8'de açık rıza silindi: tarih dolu, rıza yok dönmeli
  begin
    if (public.my_consent_status()->>'profil') = 'true' and (public.my_consent_status()->>'beyan_at') is not null
       and (public.my_consent_status()->>'riza') = 'false' and (public.my_consent_status()->>'riza_at') is null
    then passed := passed + 1; else fails := fails || 'riza_durumu_yanlis; '; end if;
  exception when others then fails := fails || 'riza_durumu_hata(' || sqlstate || '); '; end;
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  begin
    if (public.my_consent_status()->>'profil') = 'false' then passed := passed + 1;
    else fails := fails || 'profilsiz_hesap_ayirt_edilmiyor; '; end if;
  exception when others then fails := fails || 'profilsiz_riza_durumu_hata(' || sqlstate || '); '; end;
  reset role;
  -- Rıza tarihleri doğrudan okunamaz (yalnızca kişinin kendi rıza durumu işlevinden)
  if has_column_privilege('authenticated', 'public.profiles', 'acik_riza_at', 'select')
  then fails := fails || 'riza_sutunu_dogrudan_okunabiliyor; ';
  else passed := passed + 1; end if;

  -- 10c) Rızası olmayanın olayı düşer, kaydı aileye görünmez (44). Bölüm 8'de u'nun rızası silindi.
  select m2.user_id into male from public.pool_members m2 where m2.pool_id = p and m2.user_id <> u limit 1;
  insert into public.daily_prayers(user_id, prayer_date, fajr) values (u, (now() at time zone 'Europe/Istanbul')::date, 'PRAYED')
    on conflict (user_id, prayer_date) do update set fajr = 'PRAYED';
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    insert into public.pool_events(pool_id, sender_id, event_type, prayer) values (p, u, 'PRAYED', 'ISHA');
    if (select count(*) from public.pool_events where sender_id = u and prayer = 'ISHA' and created_at > now() - interval '1 minute') = 0
    then passed := passed + 1; else fails := fails || 'rizasiz_olay_dusmedi; '; end if;
  exception when others then fails := fails || 'rizasiz_olay_hata(' || sqlstate || '); '; end;
  reset role;
  if male is null then
    skipped := skipped || 'rizasiz_gorunurluk(ikinci uye yok); ';
  else
    perform set_config('request.jwt.claims', json_build_object('sub', male, 'role', 'authenticated')::text, true);
    set local role authenticated;
    if (select count(*) from public.daily_prayers where user_id = u) = 0 then passed := passed + 1;
    else fails := fails || 'rizasiz_kayit_aileye_gorunuyor; '; end if;
    reset role;
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);

  -- 9) Kaza kaydı olan hesap silinebilir (özet tetikleyicisi silmeyi bozmaz); en sonda, geri alınır
  insert into public.kaza_prayers(user_id, prayer_type, owed_count, completed_count) values (u, 'ASR', 2, 1)
    on conflict (user_id, prayer_type) do update set owed_count = excluded.owed_count + 1;
  perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    perform public.delete_my_account();
    reset role;
    if exists (select 1 from public.profiles where id = u) or exists (select 1 from public.kaza_summary where user_id = u)
    then fails := fails || 'hesap_silme_veri_kaldi; '; else passed := passed + 1; end if;
  exception when others then
    reset role;
    fails := fails || 'kazali_hesap_silinemiyor(' || sqlstate || '); ';
  end;

  if fails = '' then
    raise exception 'SONUC: OK % test gecti (geri alindi). Atlanan: %. UYARI: %', passed,
      coalesce(nullif(skipped, ''), 'yok'), coalesce(nullif(uyari, ''), 'yok');
  else
    raise exception 'SONUC: HATA % gecti; basarisiz: % Atlanan: %. UYARI: %', passed, fails,
      coalesce(nullif(skipped, ''), 'yok'), coalesce(nullif(uyari, ''), 'yok');
  end if;
end $$;
