Daha küçük güncelleme indirmesi ve güvenlik: telefon yedeğinde oturum bilgisi tutulmaz, sadece Google ile giriş.

## 🌟 Kullanıcı için

**Giriş ve gezinti**
- Açılışta **Hoş Geldiniz** penceresi: **Google ile Hızlı Giriş Yap** (telefondaki hesap seçilir, tarayıcı açılmaz) veya **Giriş Yapmadan Devam Et**.
- Gezinti modunda bütün ekranlar denenebilir; yapılanlar sadece bellekte tutulur, uygulama kapanınca silinir. Giriş yapılırsa o oturumdakiler buluta kaydedilir.

**Bugün**
- Konum uygulama her açıldığında otomatik alınır; hata olursa 10 sn sonra tekrar dener (en fazla 3). Konum bilgisi sadece Ayarlar'da. Diyanet vakitleri, SIRADAKİ VAKİT geri sayımı, günün ayeti/hadisi, kıble pusulası.
- 5 vakit kartı (ince çizgili simgeler): Kıldı → Kılmadı → Muaf → Bekliyor. Vakti girmemiş namaz ve vakitler yüklenmeden kartlar kilitli.

**Aile Havuzu**
- Herkes **Aile Ferdi** olarak başlar; giriş yapınca **EMB-123456** davet kodu hazır. Kod, paylaşım penceresiyle (WhatsApp, Gmail…) gönderilir.
- Tek bekleyen istek, **5 dakika** onay süresi, iki tarafta geri sayım.
- Reis onaylarken kendi ünvanını (🏡 Aile Reisi / 🧔 Baba / 🧕 Anne) ve katılanın ünvanını + simgesini seçer; başörtülü simgeler dahil.
- Reis, fertleri **Kızın / Oğlun / Eşin** olarak görür.
- **Bağlantıyı Teyit Et**, BEKLEMEDE / AKTİF rozeti, Bugün Aile Başarısı, ortak matris, Dünü Gör, dua gönderme, son hareketler.
- Aile bildirimleri **uygulama kapalıyken de** gelir (Firebase Cloud Messaging): dua, namaz, kaza, katılım. İşaretten 5 sn sonra son duruma göre tek bildirim; reis "Kızın dua gönderdi" gibi görür.

**Kaza**
- Kalan / Kılınan kutuları, vakit başına −/Borç/+, Kaza Kıldım.
- **Toplu Ekle: yıl** (1–20 yıl hızlı düğmeler, 1 yıl = 365 gün) **veya gün**.
- **Kaza kayıtlarını sıfırla:** iki kez onay ister (ikincisinde "SIFIRLA" yazılır).
- Aile yalnızca toplamı görür (mahremiyet korumalı).

**Karne**
- Haftalık başarı oranı, 7 günlük tarihli grafik, vakit detayı, Birlikte Secde, gerçek veriyle 5 rozet, günün hadisi.

**Bildirimler ve Ayarlar**
- Vakitten **11 dk önce** hatırlatma; eski uygulamadaki gibi **vakte özel** hadis / ayet / dua (Sabah, Öğle, İkindi, Akşam, Yatsı için ayrı ayrı). Her gün 12:00 günün ayeti.
- **Cuma:** Öğle kartı "Cuma Namazı 🕌" olur; hatırlatma "Hayırlı Cumalar! Cuma Namazına 11 Dakika Kaldı" ve Cuma'ya özel sözlerle gelir.
- **Tam zamanında hatırlatma:** "Alarm ve hatırlatıcılar" izni verilirse bildirimler dakikası dakikasına gelir (Ayarlar'da uyarı ve İzin ver düğmesi).
- Uygulama içi güncelleme, bulut durumu, Şimdi Yedekle, Uygulamayı paylaş, Öneri Yaz (mail), Hesabımı ve verilerimi sil.

**Güvenlik ve performans**
- Güncelleme telefonun işlemci türüne uygun küçük APK'yı indirir (yaklaşık 20 MB).
- Android otomatik yedeklemesi kapalı: oturum bilgisi başka cihaza taşınamaz. Namaz ve kaza kayıtların hesabına bağlı bulutta; giriş yapınca otomatik gelir.
- Sadece Google ile giriş (e-posta/şifre ile kayıt kapalı).
- Kişi başı bildirim sınırı: dua dakikada 1, saatte 3, günde 10; aynı vakit için günde en fazla 2 bildirim.
- Katılma isteği internet kesilse bile 5 dakika sonra sunucuda kendiliğinden düşer; istek iletilemezse uygulama bunu söyler.
- Aile hareketleri 1 hafta saklanır, son 5'i görünür. Aile ekranı sadece değişen kişinin satırını günceller.

## 🛠 Teknik ayrıntılar

**Uygulama:** Flutter (Dart 3), Material 3. Paket adı `com.bilkil53.aile_ile_namaz`. Görünen sürüm `1.0`; `versionCode` = derleme numarası (v1.0 ile **1**'den başladı, yalnızca resmi yayınlarda artar; yayın etiketi `r<N>`). Android güncellemeyi ve uygulama içi güncelleme kontrolü bununla çalışır.

**Paketler:** supabase_flutter ^2.8 · google_sign_in ^6.2 · geolocator ^13 · geocoding ^4 · sensors_plus ^6.1 · flutter_local_notifications ^18 (+ timezone, core library desugaring 2.1.4) · shared_preferences ^2.3 · package_info_plus ^8 · url_launcher ^6.3 · share_plus ^10.1 · open_filex ^4.6 · path_provider ^2.1 · intl ^0.19.

**Arka uç:** Supabase (eu-central-1) — PostgreSQL + Row Level Security, Auth (Google sağlayıcısı), Realtime.
- Tablolar: profiles, pools, pool_members, join_requests, daily_prayers, kaza_prayers, kaza_summary, pool_events, devices.
- RPC'ler `security definer`, yalnızca `authenticated` rolüne açık; yardımcılar `private` şemasında: ensure_my_pool, request_join (tek bekleyen istek, 5 dk, deneme sınırı, EMB öneki), approve_join_with_roles (reis ünvanı yalnızca Aile Reisi/Baba/Anne), set_member_role, transfer_ownership, remove_member, regenerate_invite_code, delete_my_account.
- Realtime: pool_events, daily_prayers, join_requests, pool_members, kaza_summary.
- Migration'lar 01–10 (son: `10_reis_icon_house`).

**Giriş:** Google Sign-In (Android OAuth istemcisi + sabit SHA-1) → ID token → `auth.signInWithIdToken`. Başarısızsa OAuth tarayıcı akışı (`prompt=select_account`, dönüş `io.supabase.aileilenamaz://login-callback/`).

**Vakitler:** aladhan.com method 13 (Diyanet) → telefonda önbellek → çevrimdışı yerel hesap. Konum geolocator + geocoding, sadece telefonda.

**Çevrimdışı ve gizlilik:**
- Giriş yapmışken işaretler önce telefona yazılır; buluta gidemezse bekleme kuyruğuna girer ve bağlantı gelince gönderilir.
- Misafir verisi yalnızca bellekte. Test dönemi önbelleği ilk açılışta bir kez temizlenir.
- `profiles.email` sütununa istemci erişimi kapalı.

**Anlık bildirim (FCM):** firebase_core ^3.6 + firebase_messaging ^15.1, Firebase projesi `aile-ile-namaz-d437f`. Cihaz adresi `devices` tablosuna (RLS: sadece sahibi) yazılır; çıkışta / aile bildirimleri kapatılınca silinir. `pool_events` ekleme tetikleyicisi (`pg_net`) → `push-family` Edge Function → FCM HTTP v1 (hizmet hesabı JWT, `aile_olaylari` kanalı). Olay `pushed_at` ile atomik işaretlenir (son 2 dk, tek sefer); geçersiz cihaz adresleri otomatik temizlenir. Uygulama ön plandayken Realtime gösterir, arka planda FCM (çift bildirim yok). Migration `11_fcm_push_trigger`.

**Bildirimler:** Yerel zamanlanmış bildirimler (3 gün ileri, BigText; `SCHEDULE_EXACT_ALARM` izni varsa `exactAllowWhileIdle`, yoksa esnek). Vakte özel söz havuzu eski uygulamadan taşındı (31 söz). Aile olayları Realtime `pool_events` dinlenerek gösterilir; vakit olayları 5 sn gecikmeli ve tekilleştirilmiş gönderilir.

**Güvenlik/performans (derleme 4):** `pool_events` BEFORE INSERT sınır tetikleyicisi (`rate_limited`), `(sender_id, created_at)` indeksi; kullanılmayan `approve_join`, `create_pool` ve `join_requests_user_idx` kaldırıldı; `join_requests.status`'a `expired`; pg_cron: `aile-expire-requests` (her dakika), `aile-cleanup` (her gece, 7 gün). Release: `--obfuscate --split-debug-info`; Firebase Crashlytics (google-services + crashlytics Gradle eklentileri).

**Derleme 5:** `allowBackup=false`, `dataExtractionRules` (bulut yedeği ve cihaz aktarımı hariç); `--split-per-abi` APK'ları (arm64-v8a, armeabi-v7a, x86_64) + evrensel APK; güncelleyici `dart:ffi Abi.current()` ile doğru APK'yı seçer. Supabase Auth: e-posta sağlayıcısı kapalı, yalnızca Google.

**Google Play:** Aynı derlemede `aile-ile-namaz.aab` (`--dart-define=STORE=play`): Play uygulama içi güncelleme (in_app_update), `REQUEST_INSTALL_PACKAGES` kaldırılmış manifest. Rehber: `docs/PLAY_STORE.md`.

**Güncelleme:** GitHub Releases API (`releases/latest`) → iç etiket numarası > yüklü `versionCode` ise APK uygulama içinde indirilir (ilerleme çubuğu) → Android kurulum ekranı.

**Derleme hattı (GitHub Actions):** `flutter create` → manifest yaması (izinler, giriş dönüş bağlantısı, bildirim alıcıları, mailto/https sorguları) → Gradle desugaring → keystore secrets ile imza → `flutter analyze` özeti → `flutter build apk --release` → `dev` dalında sadece derleme, `main` dalında GitHub Release.
