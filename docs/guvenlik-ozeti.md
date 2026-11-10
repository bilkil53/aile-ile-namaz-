# Güvenlik özeti (Supabase)

Son kontrol: 09.11.2026, canlı veritabanından okundu. Şema geçmişinin tamamı `supabase/migrations/` klasöründe (33 dosya). Her dosya sunucudaki kayıtla bayt bayt aynı (MD5 karşılaştırıldı).

## 1. Temel ilkeler

- **Her tabloda RLS açık.** Politika olmayan işlem reddedilir.
- **Uygulama yalnızca iki rolle bağlanır:**
  - `anon`: giriş yapılmamış.
  - `authenticated`: Google ile giriş yapılmış.
- **`service_role` yalnızca sunucuda kullanılır** (Edge Function `push-family`). APK'da yoktur.
- **Kritik işlemler `security definer` RPC'lerle yapılır.** Örnekler: havuz kurma, katılma, onay, ünvan, Pro.
  - Her biri `auth.uid()` boşsa hata verir.
  - Hepsinde `search_path` sabittir.
  - Tablo adları şemayla yazılır (`public.…`).
- **Yardımcı fonksiyonlar `private` şemasındadır.** API bu şemayı göstermez.
- **Kullanılmayan tablo yetkileri geri alınmıştır** (migration 29): `TRUNCATE`, `TRIGGER`, `REFERENCES`.

## 2. Tablolar, yetkiler ve politikalar

| Tablo | API yetkisi (authenticated) | RLS politikası |
|---|---|---|
| `profiles` | Sütun bazında: SELECT `id`, `display_name`, `icon`, `created_at`; UPDATE `display_name`, `icon`, `kvkk_consent_at`; açık rıza tarihi `acik_riza_at` yalnızca `record_acik_riza()` ile sunucu saatiyle yazılır | Kendisi, aynı havuzdakiler veya bana bekleyen isteği olan kişi görür; yalnızca kendini günceller. E-posta ve Pro sütunları (`pro_until`, `pro_paid_until`, `pro_trial_started_at`) API'den **okunamaz ve yazılamaz**; Pro durumu yalnızca `my_pro_status()` ile okunur. |
| `daily_prayers` | SELECT, INSERT, UPDATE, DELETE | Yazma yalnızca kendi satırına. Okuma: kendisi ve aynı havuzdakiler. Tetikleyici `block_male_excused`: erkek olarak işaretli kişinin "Muaf" kaydı boşa çevrilir. |
| `kaza_prayers` | SELECT, INSERT, UPDATE, DELETE | Yalnızca kendi satırları (ayrıntı aileye açık değil). |
| `kaza_summary` | SELECT | Kendisi ve aynı havuzdakiler (yalnızca toplam). |
| `pools` | SELECT, DELETE; UPDATE yalnızca `name` sütunu | Üyeler görür; yalnızca sahibi adını değiştirir ve siler. Oluşturma: `ensure_my_pool()` RPC. |
| `pool_members` | SELECT (sütunlar: `pool_id`, `user_id`, `role_title`, `icon`, `gender`, `joined_at`) | Aynı havuzdakiler görür. Ekleme, çıkarma ve ünvan işleri yalnızca RPC ile. |
| `join_requests` | SELECT | İsteyen kişi ve havuz sahibi görür. Yazma yalnızca RPC ile. |
| `pool_events` | SELECT, INSERT — yalnızca `pool_id`, `sender_id`, `event_type`, `message`, `prayer`, `target_id` sütunlarına (migration 31; `id`, `created_at`, `push_*` istemciden yazılamaz, tarih geriye atılıp hız sınırı atlatılamaz). UPDATE/DELETE yetkisi yok | Okuma: havuz üyesi; hedefli dua yalnızca hedef ve gönderen tarafından görülür. Ekleme: kendi adına, yalnızca PRAYED/MISSED/KAZA/DUA. MEMBER_*, PRO_* olayları yalnızca RPC'den gelir. Tetikleyiciler: hız sınırı (dua dakikada 1, saatte 3, günde 10; aynı vakit günde 2) ve bildirim kuyruğu. |
| `devices` | SELECT, INSERT, UPDATE, DELETE | Yalnızca kendi cihaz kayıtları (FCM jetonu). |
| `crash_reports` | Yalnızca INSERT (anon + authenticated) | Okunamaz, değiştirilemez; 30 günde silinir. |
| `join_attempts` | Yok | Politika yok; yalnızca RPC yazar (katılma denemesi sınırı: saatte 20). |

## 3. RPC'ler (çağıran rol: authenticated)

| Fonksiyon | Ne yapar | Korumalar |
|---|---|---|
| `ensure_my_pool()` | Kişinin tek havuzunu kurar ya da döndürür | Kişi başına 1 havuz (benzersiz indeks) |
| `request_join(code, …)` | Davet koduyla katılma isteği | Saatte 20 deneme; bekleyen tek istek; havuz en fazla 5 kişi; başka kalabalık ailedeyse reddedilir |
| `approve_join_with_roles(…)` | Reis isteği onaylar, ünvan ve cinsiyet verir | Yalnızca havuz sahibi; 5 dakikalık süre; satır kilidiyle 5 kişi sınırı |
| `reject_join`, `cancel_join_request` | İsteği reddeder / iptal eder | Sahip / isteyen |
| `set_member_role(…)` | Ünvan, simge, cinsiyet | Yalnızca havuz sahibi |
| `remove_member`, `transfer_ownership`, `regenerate_invite_code` | Havuz yönetimi | Yalnızca havuz sahibi |
| `leave_pool`, `my_outgoing_requests` | Ayrılma / kendi istekleri | Yalnızca kendisi |
| `delete_my_account()` | Hesabı ve tüm verisini siler | Kendisi; bağlı tablolar `on delete cascade` |
| `my_pro_status()`, `ensure_pro_trial()` | Pro durumu / 7 günlük deneme başlatma | Deneme yalnızca bir kez başlar |
| `redeem_pro_code(code)` | Test Pro kodu ("1") | Yalnızca Aile Reisi |
| `request_pro_from_reis()`, `decline_pro_request(member)` | Reisten Pro isteme / reddetme | 20 saatte 1 istek; reddetmeyi yalnızca o üyenin havuz sahibi yapabilir |
| `claim_push_event`, `finish_push_event` | Bildirim kuyruğu | **Yalnızca service_role** |

## 4. Zamanlanmış işler (pg_cron)

| İş | Zaman | Görev |
|---|---|---|
| `aile-expire-requests` | her dakika | 5 dakikayı geçen katılma isteklerini düşürür |
| `aile-push-retry` | her dakika | Gönderilemeyen bildirimleri yeniden dener (en fazla 3 deneme, 10 dakika içinde) |
| `aile-cleanup` | her gün 00:30 | 7 günden eski olayları ve sonuçlanmış istekleri, 1 günden eski katılma denemelerini siler (KVKK saklama süresi) |
| `aile-crash-cleanup` | her gün 00:40 | 30 günden eski çökme raporlarını siler |

## 5. Yapılan sıkılaştırma (migration 31, 8 Kasım 2026)

- `my_pro_status`, `request_pro_from_reis`, `decline_pro_request`, `test_restart_trial`, `test_remove_pro`: `anon` yetkisi alındı, yalnızca `authenticated`.
- `private.retry_push_events`, `private.block_male_excused`: API rolleri çağıramaz (cron ve tetikleyici çalışmaya devam eder).
- `ensure_pro_trial`, `redeem_pro_code`, `expire_pro_test`, `test_*`: `search_path` boş.
- `pool_events` INSERT sütun bazlı (yukarıdaki tablo).
- Geri alınan canlı testle doğrulandı: anon reddedildi; giriş yapmış kullanıcının Pro akışı ve 6 sütunla ekleme çalışıyor; `created_at` ile ekleme ve UPDATE reddedildi.

## Yapılan sıkılaştırma (migration 33, 9 Kasım 2026)

- **Bildirim fonksiyonu (`push-family`) anahtar ister:** anahtar Vault'ta üretilir (repoda ve sohbette yoktur); tetikleyici ve tekrar deneme görevi `x-push-secret` başlığıyla gönderir, fonksiyon anahtarı yalnızca `service_role` ile `push_hook_secret()`'tan okur. Anahtarsız ya da yanlış anahtarlı çağrı 401 (fail-closed; canlıda doğrulandı). Fonksiyon `verify_jwt=false` ile dağıtılmalıdır (tetikleyici JWT göndermez).
- **Telefon başına tek hesap:** `devices` tetikleyicisi aynı `fcm_token`'ı başka hesaplardan siler (aynı telefonda iki ailenin bildirimi karışmaz).
- **Hata raporları anonim:** `crash_reports.user_id` kaldırıldı; istemci yalnızca veri sütunlarına yazabilir, `created_at` sunucuda atanır (30 günlük silme atlatılamaz); saatte 300 rapor üst sınırı.
- **İç fonksiyonlar:** `pool_max_members` (search_path boş), `handle_new_user`, `refresh_kaza_summary`, `gen_invite_code` API rollerine kapalı.
- **Veri azaltma:** `profiles.email`, `daily_prayers.note`, `daily_prayers.updated_at` kaldırıldı; e-posta yalnızca Supabase Auth'ta durur.
- **İstemci (r80/r81):** telefondaki kişisel veriler tek hesaba bağlı (hesap değişince/çıkışta silinir), KVKK onayı hesap başına.

## Gönderilmemiş kayıtlar ve hesap değişimi

- Çıkışta ya da aynı telefonda başka hesap girince, önceki hesabın gönderilmemiş kayıtları **silinmez**: o hesap adına telefonda ayrı saklanır (`parked.v1`, en fazla 30 gün). Diğer hesap bunları göremez ve onun adına gönderemez; aynı hesap tekrar girince kuyruğa geri yüklenir ve otomatik gönderilir. Hesap silinirse saklananlar da silinir. Çıkışta bekleyen kayıt varsa kullanıcıya bu bilgi gösterilir.

## Sunucu güvenlik testi CI'da

- `.github/workflows/build-apk.yml` "Sunucu güvenlik testi" adımı, GitHub gizli ayarı `SUPABASE_DB_URL` ile `security_test.sql`'i her derlemede zorunlu çalıştırır; "SONUC: OK" yoksa ya da ayar tanımlı değilse derleme ve yayın durur (fail-closed).
- **Kurulum (proje sahibi yapar, şifre içerir):** Supabase → Project Settings → Database → Connection string → *Session pooler* (5432) adresini kopyalayın, şifreyi yerleştirin; GitHub → Settings → Secrets and variables → Actions → *New repository secret*: ad `SUPABASE_DB_URL`.
- Test her çalışmada **UYARI** olarak bilinen açığı da raporlar: `test_restart_trial` ve `test_remove_pro` giriş yapmış herkese açık (demo test paneli için bilerek; ücretli Pro'dan önce kapatılacak).

## İmza kontrolü (fail-closed)

- `lib/integrity.dart`: GitHub'dan dağıtılan sürümlerde (stabil ve demo) uygulama açılışta kendi imzasının SHA-256'sını beklenenle karşılaştırır. **Tutmazsa ya da okunamazsa uygulama açılmaz**: kapatılamayan pencerede yalnızca "Resmi sürümü indir" ve "Kapat" vardır; kontrol bütün açılış işlerinden önce çalışır.
- Google Play sürümünde (`STORE=play`) bu kontrol yapılmaz: Play uygulamayı kendi anahtarıyla yeniden imzalar, kontrol gerçek kullanıcıları kilitlerdi. Play'e çıkışta doğru yöntem **Play Integrity API** + sunucu tarafı doğrulamadır.
- Kendini kilitleme koruması: CI, `MainActivity` imza okuyucusunu içermiyorsa ya da beklenen imza (`EXPECTED_SIG`) main/demo'da boşsa yayını durdurur. Karar mantığı `test/integrity_test.dart` ile sınanır.
- Sınır: değiştirilmiş bir APK bu kontrolü de silebilir; bu yüzden yetki kontrolü her zaman sunucuda (RLS, sütun yetkileri, RPC'ler; 20 kontrollük test) yapılır.

## 6. İstemci tarafı notlar

- **APK imza kontrolü (`lib/integrity.dart`) bir güvenlik sınırı değildir.** İmza uyuşmazsa kullanıcı uyarılır ama uygulama engellenmez; değiştirilmiş bir APK bu kontrolü zaten atlayabilir. Bütün yetkilendirme sunucuda yapılır: RLS politikaları, sütun yetkileri ve `security definer` RPC'ler (bkz. bölüm 2–3, `supabase/tests/security_test.sql`). İstemciden gelen hiçbir bilgiye (imza, Pro durumu, rol) güvenilmez.
- **Hata raporları:** hiçbir şey otomatik gönderilmez; yalnızca kişi pencerede "Raporu gönder" ya da "Mail ile" derse gider. `crash_reports`'a ve geliştirici mailine gitmeden önce hata metni ve yığın izi `scrubSensitive` ile temizlenir: e-posta, JWT/Bearer, `access_token`/`apikey`/`password` vb. değerleri, `?code=`, uuid, telefon, veritabanı hata ayrıntısındaki satır değerleri ("Failing row contains", "Key (…)=" — ad, dua metni), uygulama klasörü yolları (`/data/user/…`), ortak depolamadaki dosya adları ve 40+ karakterli anahtar benzeri diziler. Hata kodları, satır numaraları ve sunucu adresi korunur. Telefondaki hata kaydı (`Log`) da aynı şekilde temizlenir. Kişi adı gibi serbest metinler otomatik tanınamaz; hata metinlerine ad yazılmamalı.
- **Gezinti (misafir) modu yalnızca görüntüleme:** kayıt yapılmaz, giriş sonrası aktarım yoktur (`Repo.setPrayer`/`saveKaza` misafirde hiçbir şey yazmaz). Sunucuda da misafir (anon) yalnızca anonim hata raporu yazabilir; başka hiçbir tabloya yazamaz. Eski aktarım fonksiyonu `merge_guest_kaza` ve `guest_merges` tablosu migration 32 ile kaldırıldı.

## 7. Bilinen açık işler

1. **Play'e çıkmadan önce (ücretli Pro başlamadan) silinecek TEST fonksiyonları — öncelikli.** Şu an her giriş yapmış kullanıcı deneme süresini sıfırlayıp "1" koduyla Pro alabilir. Fonksiyonlar: `test_restart_trial`, `test_remove_pro`, `expire_pro_test`. `redeem_pro_code` ("1" kodu) yerine Google Play ödeme doğrulaması gelecek.
2. **Testler (eklendi, 08.11.2026).** `test/` altındaki birim testleri CI'da her derlemede çalışır; biri başarısız olursa yayın çıkmaz. `supabase/tests/security_test.sql` sunucu kurallarını (anon yetkileri, `pool_events` sütun yetkisi, hız sınırı, misafirin kayıt yazamaması, gizlilik, erkek üyede "Muaf" kuralı) geri alınarak sınar; her sunucu değişikliğinden sonra çalıştırılmalı. Eksik: ekran (widget) testleri.
