İlk resmi sürüm: Aile Havuzu, Diyanet vakitleri, kaza takibi, karne ve bildirimler.

## 🌟 Kullanıcı için

**Giriş ve gezinti**
- Açılışta **Hoş Geldiniz** penceresi: **Google ile Hızlı Giriş Yap** (telefondaki hesap seçilir, tarayıcı açılmaz) veya **Giriş Yapmadan Devam Et**.
- Gezinti modunda bütün ekranlar denenebilir; yapılanlar sadece bellekte tutulur, uygulama kapanınca silinir. Giriş yapılırsa o oturumdakiler buluta kaydedilir.

**Bugün**
- GPS ile otomatik ilçe/il, Diyanet vakitleri, SIRADAKİ VAKİT geri sayımı, günün ayeti/hadisi, kıble pusulası.
- 5 vakit kartı (ince çizgili simgeler): Kıldı → Kılmadı → Muaf → Bekliyor. Vakti girmemiş namaz ve vakitler yüklenmeden kartlar kilitli.

**Aile Havuzu**
- Herkes **Aile Ferdi** olarak başlar; giriş yapınca **EMB-123456** davet kodu hazır. Kod, paylaşım penceresiyle (WhatsApp, Gmail…) gönderilir.
- Tek bekleyen istek, **5 dakika** onay süresi, iki tarafta geri sayım.
- Reis onaylarken kendi ünvanını (🏡 Aile Reisi / 🧔 Baba / 🧕 Anne) ve katılanın ünvanını + simgesini seçer; başörtülü simgeler dahil.
- Reis, fertleri **Kızın / Oğlun / Eşin** olarak görür.
- **Bağlantıyı Teyit Et**, BEKLEMEDE / AKTİF rozeti, Bugün Aile Başarısı, ortak matris, Dünü Gör, dua gönderme, son hareketler.
- Aile bildirimleri: işaretten 5 sn sonra son duruma göre tek bildirim.

**Kaza**
- Kalan / Kılınan kutuları, vakit başına −/Borç/+, Kaza Kıldım.
- **Toplu Ekle: yıl** (1–20 yıl hızlı düğmeler, 1 yıl = 365 gün) **veya gün**.
- Aile yalnızca toplamı görür (mahremiyet korumalı).

**Karne**
- Haftalık başarı oranı, 7 günlük tarihli grafik, vakit detayı, Birlikte Secde, gerçek veriyle 5 rozet, günün hadisi.

**Bildirimler ve Ayarlar**
- Vakitten **11 dk önce** hatırlatma; eski uygulamadaki gibi **vakte özel** hadis / ayet / dua (Sabah, Öğle, İkindi, Akşam, Yatsı için ayrı ayrı). Her gün 12:00 günün ayeti.
- **Cuma:** Öğle kartı "Cuma Namazı 🕌" olur; hatırlatma "Hayırlı Cumalar! Cuma Namazına 11 Dakika Kaldı" ve Cuma'ya özel sözlerle gelir.
- **Tam zamanında hatırlatma:** "Alarm ve hatırlatıcılar" izni verilirse bildirimler dakikası dakikasına gelir (Ayarlar'da uyarı ve İzin ver düğmesi).
- Uygulama içi güncelleme, bulut durumu, Şimdi Yedekle, Uygulamayı paylaş, Öneri Yaz (mail), Hesabımı ve verilerimi sil.

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

**Bildirimler:** Yerel zamanlanmış bildirimler (3 gün ileri, BigText; `SCHEDULE_EXACT_ALARM` izni varsa `exactAllowWhileIdle`, yoksa esnek). Vakte özel söz havuzu eski uygulamadan taşındı (31 söz). Aile olayları Realtime `pool_events` dinlenerek gösterilir; vakit olayları 5 sn gecikmeli ve tekilleştirilmiş gönderilir.

**Güncelleme:** GitHub Releases API (`releases/latest`) → iç etiket numarası > yüklü `versionCode` ise APK uygulama içinde indirilir (ilerleme çubuğu) → Android kurulum ekranı.

**Derleme hattı (GitHub Actions):** `flutter create` → manifest yaması (izinler, giriş dönüş bağlantısı, bildirim alıcıları, mailto/https sorguları) → Gradle desugaring → keystore secrets ile imza → `flutter analyze` özeti → `flutter build apk --release` → `dev` dalında sadece derleme, `main` dalında GitHub Release.
