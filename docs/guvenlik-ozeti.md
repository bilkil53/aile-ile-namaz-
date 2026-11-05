# Güvenlik özeti (Supabase)

Son kontrol: 05.11.2026, canlı veritabanından okundu. Şema geçmişinin tamamı `supabase/migrations/` klasöründe (30 dosya). Her dosya sunucudaki kayıtla bayt bayt aynı (MD5 karşılaştırıldı).

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
| `profiles` | Sütun bazında: SELECT `id`, `display_name`, `icon`, `created_at`; UPDATE `display_name`, `icon`, `kvkk_consent_at` | Kendisi, aynı havuzdakiler veya bana bekleyen isteği olan kişi görür; yalnızca kendini günceller. E-posta ve Pro sütunları (`pro_until`, `pro_paid_until`, `pro_trial_started_at`) API'den **okunamaz ve yazılamaz**; Pro durumu yalnızca `my_pro_status()` ile okunur. |
| `daily_prayers` | SELECT, INSERT, UPDATE, DELETE | Yazma yalnızca kendi satırına. Okuma: kendisi ve aynı havuzdakiler. Tetikleyici `block_male_excused`: erkek olarak işaretli kişinin "Muaf" kaydı boşa çevrilir. |
| `kaza_prayers` | SELECT, INSERT, UPDATE, DELETE | Yalnızca kendi satırları (ayrıntı aileye açık değil). |
| `kaza_summary` | SELECT | Kendisi ve aynı havuzdakiler (yalnızca toplam). |
| `pools` | SELECT, DELETE; UPDATE yalnızca `name` sütunu | Üyeler görür; yalnızca sahibi adını değiştirir ve siler. Oluşturma: `ensure_my_pool()` RPC. |
| `pool_members` | SELECT (sütunlar: `pool_id`, `user_id`, `role_title`, `icon`, `gender`, `joined_at`) | Aynı havuzdakiler görür. Ekleme, çıkarma ve ünvan işleri yalnızca RPC ile. |
| `join_requests` | SELECT | İsteyen kişi ve havuz sahibi görür. Yazma yalnızca RPC ile. |
| `pool_events` | SELECT, INSERT (UPDATE/DELETE yetkisi var ama **politika yok → reddedilir**; migration 31 ile yetki de alınacak) | Okuma: havuz üyesi; hedefli dua yalnızca hedef ve gönderen tarafından görülür. Ekleme: kendi adına, yalnızca PRAYED/MISSED/KAZA/DUA. MEMBER_*, PRO_* olayları yalnızca RPC'den gelir. Tetikleyiciler: hız sınırı (dua dakikada 1, saatte 3, günde 10; aynı vakit günde 2) ve bildirim kuyruğu. |
| `devices` | SELECT, INSERT, UPDATE, DELETE | Yalnızca kendi cihaz kayıtları (FCM jetonu). |
| `crash_reports` | Yalnızca INSERT (anon + authenticated) | Okunamaz, değiştirilemez; 30 günde silinir. |
| `join_attempts` | Yok | Politika yok; yalnızca RPC yazar (katılma denemesi sınırı: saatte 20). |
| `guest_merges` | Yok | Politika yok; yalnızca `merge_guest_kaza` yazar. |

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
| `merge_guest_kaza(merge_id, items)` | Misafir kaza sayılarını hesaba ekler | Tek işlem; aynı `merge_id` ikinci kez eklenmez; tür ve sayı (0–100000) doğrulanır |
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

## 5. Bilinen açık işler

1. **Bekleyen sıkılaştırma (migration 31, uygulanmadı).** Bazı fonksiyonlar hâlâ `anon` tarafından çağrılabiliyor: `my_pro_status`, `request_pro_from_reis`, `decline_pro_request`, `test_restart_trial`, `test_remove_pro`.
   - Hepsi `auth.uid()` boşsa durduğu için şu an kötüye kullanılamıyor.
   - Yine de `anon` yetkisi geri alınacak.
   - 5 fonksiyonun `search_path`'i `public` yerine boş yapılacak: `ensure_pro_trial`, `redeem_pro_code`, `expire_pro_test`, `test_*`.
   - **`pool_events` sütun yetkisi.** Şu an istemci eklerken `id`, `created_at` ve `push_*` sütunlarını da yazabiliyor.
     - `created_at` geçmişe atılırsa hız sınırı sayımı atlatılıp aile akışına çok sayıda olay yazılabilir. Bu olaylara bildirim gitmez (kuyruk 10 dakikadan eski olayı almaz) ve ertesi gün temizlenir.
     - Çözüm: INSERT yalnızca `pool_id`, `sender_id`, `event_type`, `message`, `prayer`, `target_id` sütunlarına açılacak. Uygulama zaten yalnızca bunları gönderiyor.
2. **Play'e çıkmadan önce silinecek TEST fonksiyonları:** `test_restart_trial`, `test_remove_pro`, `expire_pro_test`. `redeem_pro_code` ("1" kodu) yerine Google Play ödeme doğrulaması gelecek.
3. **Otomatik testler henüz yok** (sonraki adım): Flutter birim testleri ve SQL test dosyası.
