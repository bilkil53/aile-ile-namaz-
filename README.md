# 👨‍👩‍👧‍👦 Aile ile Namaz — v1.0

<p align="center">
  <b>Aile Havuzu & İbadet Halkası · Diyanet Vakitleri · Kaza Takibi · İbadet Karnesi · Kıble Pusulası</b>
</p>

<p align="center">
  <a href="https://github.com/bilkil53/aile-ile-namaz-/releases/latest/download/aile-ile-namaz.apk">
    <img src="https://img.shields.io/badge/İndir-Aile%20ile%20Namaz%20(APK)-0E5A4A?style=for-the-badge&logo=android&logoColor=white" alt="APK İndir" />
  </a>
  <a href="https://github.com/bilkil53/aile-ile-namaz-/releases/latest">
    <img src="https://img.shields.io/github/v/release/bilkil53/aile-ile-namaz-?style=for-the-badge&color=0E5A4A&label=Son%20Sürüm&display_name=release" alt="Son Sürüm" />
  </a>
  <img src="https://img.shields.io/badge/Flutter-Android-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Supabase-PostgreSQL%20%2B%20RLS-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white" alt="Supabase" />
  <img src="https://img.shields.io/badge/Vakitler-T.C.%20Diyanet%20Yöntemi-green?style=for-the-badge" alt="Diyanet" />
</p>

> *"Ailene namazı emret ve kendin de onda devamlı ol."* (Tâhâ Suresi, 132)  
> *"Hep birlikte Allah'ın ipine sımsıkı sarılın, fırkalara bölünüp parçalanmayın."* (Âl-i İmrân Suresi, 103)

---

## 📱 İndirme ve Kurulum

👉 **[📥 Aile ile Namaz — En Güncel APK'yı İndir](https://github.com/bilkil53/aile-ile-namaz-/releases/latest/download/aile-ile-namaz.apk)**

1. Telefonda linke dokun, APK insin.
2. İnen dosyayı aç; Android "bilinmeyen kaynaklardan yükleme" izni isterse ver.
3. Açılan **Hoş Geldiniz** penceresinde **Google ile Hızlı Giriş Yap**'a dokun ve telefondaki Gmail hesabını seç. İstersen **Giriş Yapmadan Devam Et** ile önce gezinebilirsin.

> **Not (31.10.2026):** Derleme 6–11 arasında uygulama içi güncelleme yeni sürümü görmüyordu. Bir kez telefonuna uygun APK'yı elle kur, sonrası yine otomatik: çoğu telefon için [aile-ile-namaz-arm64-v8a.apk](https://github.com/bilkil53/aile-ile-namaz-/releases/latest/download/aile-ile-namaz-arm64-v8a.apk) (eski telefonlarda [armeabi-v7a](https://github.com/bilkil53/aile-ile-namaz-/releases/latest/download/aile-ile-namaz-armeabi-v7a.apk)).

**Güncellemeler otomatik:** Uygulama her açılışta GitHub'daki son sürümü kontrol eder. "Güncelle"ye dokununca APK uygulamanın içinde iner ve Android'in kurulum ekranı açılır. Verilerin ve girişin korunur.

**Sürüm:** Uygulamada ve GitHub'da sadece **v1.0** yazar; yayınlar tarih ve saatle ayrılır (ör. *v1.0 — 31.10.2026 12:45*). Büyük bir değişiklikte **v2.0**'a geçilir. Arka planda derleme numarası tutulur (v1.0 ile **1**'den başladı, her resmi yayında bir artar; Android güncellemeyi bununla tanır), ekranda görünmez.

---

## 🌟 Özellikler

### 1. 🕌 Bugün — Vakitler ve Günlük İbadet
* **Selamün aleyküm** karşılaması ve tarih. Konum uygulama her açıldığında **otomatik** alınır (alınamazsa 10 sn sonra tekrar, en fazla 3 deneme); konum bilgisi ve yenileme sadece **Ayarlar**'da.
* **SIRADAKİ VAKİT** kartı: geri sayım ve günün 6 vakti (İmsak, Güneş, Öğle/Cuma, İkindi, Akşam, Yatsı).
* **5 vakit kartı** (ince çizgili simgelerle): dokundukça **Kıldı → Kılmadı → Muaf → Bekliyor** (Muaf sadece kadınlarda; cinsiyeti Aile Reisi ünvanla birlikte verir). Aileye bildirim 15 sn, buluta kayıt 20 sn sonra gider; internet yoksa telefonda bekler ve otomatik gönderilir. Vakti girmemiş namaz ve vakitler yüklenmeden tüm kartlar 🔒 kilitlidir.
* **← Dün / Bugün** geçişi: unuttuğun dünkü vakitleri işaretleyebilirsin.
* **Günün Ayeti / Hadisi** (Arapça metin + Diyanet meali).
* **🧭 Kıble Pusulası:** İnternet gerektirmez; ivme + manyetik sensörle Kâbe yönü.

### 2. 👨‍👩‍👧‍👦 Aile Havuzu • İbadet Halkası
* Uygulamayı kuran herkes **Aile Ferdi** olarak başlar (**Bireysel Mod**). Giriş yapınca **EMB-123456** biçiminde davet kodun otomatik hazırdır.
* **Davet kodunu paylaş:** Telefonun paylaşım penceresiyle WhatsApp, Gmail, Mesajlar… (mesajda kod ve indirme linki hazır).
* **Katılma:** Aile ferdi sadece kodu girer. **Aynı anda tek istek** gönderilebilir; istek **5 dakika** içinde onaylanmazsa düşer. İki tarafta canlı geri sayım.
* **Reis onayı:** Reis, onaylarken **kendi ünvanını** (🏡 Aile Reisi / 🧔 Baba / 🧕 Anne) ve katılanın ünvanını + simgesini seçer (Eşi, Oğlu, Kızı, Annesi, Babası, Kardeşi, Torunu, Gelini, Damadı, Dedesi, Ninesi). Başörtülü simgeler (6 ten rengi) dahil.
* **Sahiplik hissi:** Reis, aile fertlerini **"Kızın, Oğlun, Eşin"** olarak görür; diğer üyeler ünvanı reise göre ("Kızı, Oğlu") görür.
* **Bağlantıyı Teyit Et 🔄:** Sunucudan bağlantı / istek durumunu sorgular. **BEKLEMEDE / AKTİF** rozeti, **Bireysel Mod / Aile Modu** profil kartı.
* **Ortak Matris:** Ailenin 5 vakit durumu (vakit × kişi), **"Bugün Aile Başarısı: x / y Vakit (%)"**, **◄ Dünü Gör**. Yalnızca gerçekten işaretlenen vakitler görünür; boş vakitler "—".
* **🤲 Aileye Dua Gönder**, üye kartında **Tebrik Et & Dua Gönder**, **Son Hareketler** akışı.
* **Reis yetkileri:** Ünvan/simge değiştirme, reisliği devretme, üyeyi çıkarma, kodu yenileme, **Havuzu Kapat & Sıfırla**.
* **Aile bildirimleri (uygulama kapalıyken de):** Aileden biri namaz kılınca, kaza eda edince, dua gönderince veya katılınca telefona bildirim düşer (Firebase Cloud Messaging). Kıldı/kılmadı işaretinden **5 saniye sonra** son duruma göre **tek** bildirim gider.

### 3. 📿 Kaza Takibi (Mahremiyet Korumalı)
* **Kalan Kaza Borcu / Kılınan Kaza** kutuları ve ilerleme çubuğu.
* 6 vakit (vitir dahil): "Farz: 4 Rekat | Kılınan: X", **− / Borç / +**, **Kaza Kıldım** veya **Kaza Borcu Yok (Elhamdülillah)**.
* **Sıfırla:** Tüm kaza kayıtlarını sıfırlar; iki kez onay ister (ikincisinde "SIFIRLA" yazılır).
* **Toplu Ekle:** **Yıl** (hızlı: 1, 2, 3, 5, 10, 15, 20 yıl; 1 yıl = 365 gün) veya **gün** olarak.
* **Aile Fertleri Kaza Durumu (Detaysız):** Aile yalnızca toplamı görür; hangi vakit olduğu sadece sahibine açıktır.

### 4. 🏆 İbadet Karnesi
* **Haftalık başarı oranı**, Kılınan Vakit (x/35), Eda Edilen Kaza, Aile Uyumu.
* Tarihli **7 günlük grafik** (güne dokun → vakit detayı) ve **Bugünün Vakit Detayı**.
* **Birlikte Secde:** Ailenle aynı vakti kıldığın sayı (gerçek veriden).
* **5 manevi rozet** (gerçek veriden): Sabah Namazı Muhafızı, 5'te 5 Sadakati, Kaza Avcısı, İbadet Kardeşliği, İstikrar Yıldızı.
* **Günün Hadis-i Şerifi.**

### 5. 🔔 Bildirimler
* Her vakitten **11 dakika önce** hatırlatma; eski uygulamadaki gibi **vakte özel** hadis / ayet / dua.
* **Cuma:** "Cuma Namazı 🕌" kartı ve "Hayırlı Cumalar!" hatırlatması.
* **Tam zamanında:** "Alarm ve hatırlatıcılar" izniyle dakikası dakikasına (izin yoksa Ayarlar'da uyarı).
* Her gün **12:00**'de günün ayeti / hadisi.
* **Aile bildirimleri** (5 sn gecikmeli, tek bildirim). Hepsi Ayarlar'dan açılıp kapatılabilir.

### 6. ⚙️ Ayarlar
* Sürüm + **Güncel / Yeni Sürüm** rozeti, **Güncellemeleri Kontrol Et**, uygulama içi kurulum.
* **Veritabanı Durumu:** Bulut Senkronize ☁️ / Gezinti 👀, **Şimdi Yedekle**, bekleyen kayıt sayısı.
* Konum (GPS), hatırlatma anahtarları, **Uygulamayı paylaş** (paylaşım penceresi), **Öneri Yaz** (mail uygulaması), gizlilik politikası, **Hesabımı ve verilerimi sil**.

### 7. 👀 Gezinti Modu (giriş yapmadan)
* Bütün ekranlar, Aile Havuzu dahil, denenebilir. Yapılanlar **sadece bellekte** tutulur; uygulama kapanınca silinir.
* Giriş yapılırsa o oturumdakiler buluta kaydedilir (kaza sayıları hesaptakilerin üzerine eklenir).

---

## 🔒 Güvenlik ve Gizlilik

| Konu | Eski sürüm (Kotlin) | v1.0 |
|---|---|---|
| Aile verisi | Herkese açık ntfy kanalları | Supabase + satır düzeyi güvenlik (RLS): sadece havuz üyeleri görür |
| Davet kodu | `REIS-00XXXX` (tahmin edilebilir) | `EMB-` + 6 rastgele rakam, deneme sınırı, tek bekleyen istek, 5 dk süre (sunucu her dakika süresi dolanı düşürür), reis onayı |
| Bildirim taşması | — | Kişi başı sınır: dua dakikada 1 / saatte 3 / günde 10; aynı vakit günde 2 |
| Kod | — | Release derlemesi karıştırılmış (obfuscate) |
| E-posta | Kanallarda dolaşıyordu | `profiles.email` sütununa istemci erişimi kapalı; hiçbir kullanıcı diğerinin e-postasını göremez |
| Kaza detayı | — | Veritabanı kuralıyla sadece sahibine açık; aile `kaza_summary` toplamını görür |
| Ünvan değiştirme | Herkes | Sadece Aile Reisi (sunucu fonksiyonunda kontrol) |
| Konum | — | Sadece telefonda; sunucuya gönderilmez |
| Misafir verisi | — | Telefona yazılmaz, sadece bellekte |
| Telefon yedeği | — | Android otomatik yedeklemesi kapalı; oturum bilgisi başka cihaza taşınamaz. Kişisel kayıtlar hesaba bağlı bulutta |
| Giriş yöntemi | — | Sadece Google; e-posta/şifre ile kayıt kapalı |
| Hesap silme | — | Uygulamadan; dolu havuzların reisliği en eski üyeye geçer |
| İmza anahtarı | — | GitHub Secrets'ta; repoda değil |

📄 [Gizlilik Politikası](https://bilkil53.github.io/aile-ile-namaz-/privacy.html) · 🗑 [Hesap silme](https://bilkil53.github.io/aile-ile-namaz-/delete-account.html) · 🏪 [Play Store rehberi](docs/PLAY_STORE.md)

---

## 📦 Teknik Mimari

| Katman | Kullanılan |
|---|---|
| Uygulama | Flutter (Dart 3), Material 3, tek kod tabanı · görünen sürüm `1.0`, `versionCode` = derleme no (1'den başlar) |
| Arka uç | Supabase — PostgreSQL 15, Row Level Security, Auth, Realtime (Frankfurt / eu-central-1) |
| Giriş | Google Sign-In (telefondaki hesap seçici → `signInWithIdToken`); yedek: OAuth tarayıcı akışı, `io.supabase.aileilenamaz://login-callback/` |
| Vakitler | aladhan.com, method 13 (Diyanet) → önbellek → çevrimdışı yerel hesap; 81 il koordinatı |
| Konum | geolocator (son bilinen → anlık konum), geocoding (İlçe, İl); her açılışta otomatik, hata olursa 10 sn arayla 3 deneme; arka plandan dönüşte 1 saatten eskiyse yenilenir |
| Bildirim | flutter_local_notifications (zamanlanmış, 3 gün ileri, kesin alarm) · aile olayları: ön planda Realtime, arka planda **FCM** (`push-family` Edge Function, Firebase `aile-ile-namaz-d437f`) |
| Çevrimdışı | shared_preferences önbelleği + bekleme kuyruğu (aynı vakit için en son kayıt) |
| Güncelleme | GitHub Releases API → telefonun işlemci türüne uygun APK (arm64-v8a / armeabi-v7a / x86_64, yaklaşık 20 MB; bulunamazsa hepsini içeren APK) uygulama içinde indirilir → open_filex ile kurulum · Play sürümünde Google Play uygulama içi güncelleme |
| Derleme | GitHub Actions: `flutter create` → manifest/Gradle yaması → imzalı, karıştırılmış APK (GitHub) + AAB (Google Play) → GitHub Releases |
| Hata takibi | Firebase Crashlytics |
| Zamanlanmış görevler | pg_cron: süresi dolan istekleri her dakika düşürür; her gece 7 günden eski aile hareketlerini temizler |

### Paketler
`supabase_flutter ^2.8` · `firebase_core ^3.6` · `firebase_messaging ^15.1` · `firebase_crashlytics ^4.1` · `in_app_update ^4.2` · `google_sign_in ^6.2` · `geolocator ^13` · `geocoding ^4` · `sensors_plus ^6.1` · `flutter_local_notifications ^18` · `timezone` · `shared_preferences ^2.3` · `package_info_plus ^8` · `url_launcher ^6.3` · `share_plus ^10.1` · `open_filex ^4.6` · `path_provider ^2.1` · `intl ^0.19`

### Kod yapısı
```
lib/
  main.dart            AuthGate: oturum → HomeShell, yoksa gezinti + Hoş Geldiniz penceresi
  config.dart          Supabase URL, publishable anahtar, Google web client ID
  data.dart            Repo: tüm Supabase sorguları ve RPC'ler, çevrimdışı kuyruk, misafir aktarımı
  local_store.dart     Önbellek, bekleme kuyruğu, bellekteki misafir verisi
  models.dart          PrayerStatus, Pool, Member, JoinRequest, PoolEvent, ünvanlar
  prayer_times.dart    Diyanet vakitleri, 81 il, kıble açısı
  location.dart        GPS → ilçe/il
  notifications.dart   Vakit hatırlatmaları, günün içeriği, aile bildirimleri
  push.dart            Firebase anlık bildirim: cihaz kaydı (devices)
  update_checker.dart  GitHub Releases'tan uygulama içi güncelleme
  screens/             today, family, kaza, karne, settings, login (Hoş Geldiniz), home_shell
  widgets/             prayer_icon (vakit simgeleri), qibla_card (pusula)
  content/             günlük ayet, hadis, dua, özlü söz, tebrikler
```

### Veritabanı
Tablolar: `profiles`, `pools` (owner = Aile Reisi, `invite_code` EMB…), `pool_members` (ünvan + simge), `join_requests` (5 dk), `daily_prayers`, `kaza_prayers` (sadece sahibi), `kaza_summary` (üyeler toplamı görür), `pool_events` (aile akışı + bildirim), `devices`.

Sunucu fonksiyonları (`security definer`, sadece `authenticated`): `ensure_my_pool`, `create_pool`, `request_join`, `approve_join_with_roles`, `reject_join`, `cancel_join_request`, `my_outgoing_requests`, `leave_pool`, `remove_member`, `transfer_ownership`, `set_member_role`, `regenerate_invite_code`, `delete_my_account`. Yardımcı fonksiyonlar `private` şemasında.

Realtime yayını: `pool_events`, `daily_prayers`, `join_requests`, `pool_members`, `kaza_summary`.

Anlık bildirim: `pool_events` ekleme tetikleyicisi (`pg_net`) → Edge Function `supabase/functions/push-family` → FCM HTTP v1. Gizli ayar `FCM_SERVICE_ACCOUNT` (Supabase Edge Function secret, Firebase hizmet hesabı JSON'u); repoda yoktur.

Migration'lar: `01_core_tables` → `02_helpers_rls_grants` → `03_rpc_triggers_realtime` → `04_family_flow_v118` → `05_drop_join_by_email` → `06_hide_profile_emails` → `07_titles_relative_to_reis` → `08_auto_pool` → `09_emb_codes_5min_titles_delete` → `10_reis_icon_house` → `11_fcm_push_trigger` → `12_rate_limit_cleanup_retention` → `13_cleanup_fix` → `14_device_notification_prefs` → `15_member_gender_by_reis`.

### Derleme ve dallar
* `dev` → test derlemesi (yayınlanmaz) · `main` → resmi yayın (başlık *v1.0 — tarih saat*, etiket `r1`, `r2`, …; derleme no = son `r` etiketi + 1).
* Sürüm açıklaması `RELEASE_NOTES.md` dosyasından + derleme bilgisiyle otomatik oluşur; ilk satır uygulama içi güncelleme penceresinde görünür.
* İmza: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD` (GitHub Secrets). SHA-1 sabit kaldığı için Google girişi her sürümde çalışır.

### Geliştiriciler için
```bash
flutter create . --org com.bilkil53 --project-name aile_ile_namaz --platforms android
flutter pub get
flutter run
```
`lib/config.dart` içindeki anahtar **publishable** anahtardır (istemcide olması normaldir). `service_role` anahtarını asla repoya koyma.

---

## 📋 Sürüm Geçmişi

### v1.0 — İlk resmi sürüm (31 Ekim 2026)
Yukarıdaki tüm özellikler. Görünen sürüm **v1.0**; güncellemeler tarihle ayrılır.
Bu sürümdeki son eklemeler:
* Toplu kaza eklemede **yıl** seçeneği ve hızlı yıl düğmeleri.
* Reis için sahiplik ekli ünvanlar (**Kızın, Oğlun, Eşin**).
* Vakte özel hatırlatma sözleri, Cuma kartı ve hatırlatması, tam zamanında (kesin alarm) hatırlatma.
* Derleme numarası **1**'den başladı.
* **Derleme 12:** Düzeltme: küçük (işlemci türüne göre) APK'larda Android sürüm kodu 3000+N olduğu için uygulama içi güncelleme yeni sürümü görmüyordu; karşılaştırma artık derleme numarasıyla yapılıyor. Bir kez elle kurulum gerekir (aşağıya bakın).
* **Derleme 11:** Cinsiyeti Aile Reisi verir: katılımı onaylarken ve ünvan değiştirirken ünvan + simge + cinsiyet (🧔 Erkek / 🧕 Kadın); reis "Aile Reisi" seçerse kendi cinsiyetini de seçer (Baba/Anne'de otomatik). Muaf buna göre gösterilir; kullanıcıya sorulan cinsiyet penceresi ve Ayarlar'daki seçim kaldırıldı.
* **Derleme 10:** Ayarlar'da "Sıradaki hatırlatma: Yatsı 19:20 (vakit 19:31)" satırı ve hatırlatmanın tam zamanında mı yoksa gecikmeli mi geleceği bilgisi.
* **Derleme 9:** Aile Havuzu internetsiz de açılır (ailenin son bilinen durumu + "İnternet yok" uyarısı, bağlantı gelince kendiliğinden yenilenir). Kilit ekranı ve cinsiyet soruları internet beklemeden hemen sorulur; açılıştaki ağ işleri arka plana alındı.
* **Derleme 8:** Kıldı/kılmadı: aileye bildirim 15 sn, buluta yazma 20 sn sonra (son duruma göre). İlk açılışta "Telefon kilitliyken bildirim yazısı görünsün mü?" sorusu. Cinsiyet seçimi (Ayarlar + ünvandan anlaşılmıyorsa bir kez sorulur): Muaf sadece kadınlarda.
* **Derleme 7:** İnternet yokken uygulama açılışta takılmıyor (oturum telefondan yüklenir, en fazla 3 sn beklenir); ad ve kayıtlar çevrimdışı telefondan gösterilir, ağ isteklerine zaman aşımı eklendi.
* **Derleme 6:** Kıldı/kılmadı buluta da 5 saniye sonra yazılır (aile matrisi ve bildirim son duruma göre); internet yoksa telefonda bekler, 20 saniyede bir arka planda tekrar denenir. Erkek ünvan/simgelerde "Muaf" seçeneği yok. Bildirimlerde kişinin simgesi (ör. "🧕🏻 Kızın kaza namazı kıldı"). Ayarlar'da hangi aile bildirimlerinin alınacağı (namaz / kaza / dua) ve kilit ekranında içerik gösterimi.
* **Derleme 5:** Android otomatik yedeklemesi kapatıldı (oturum bilgisi Drive'a/başka cihaza taşınmaz; kişisel kayıtlar zaten bulutta ve girişte geri gelir); sadece Google ile giriş (e-posta/şifre kaydı kapatıldı); güncelleme telefonun işlemci türüne uygun küçük APK'yı indirir.
* **Derleme 4:** Güvenlik ve Play hazırlığı: kişi başı bildirim sınırı (dua: dakikada 1, saatte 3, günde 10; aynı vakit günde 2), süresi dolan istekler sunucuda otomatik düşer, eski onay fonksiyonu kaldırıldı, aile hareketleri 1 hafta saklanır ve son 5'i görünür, aile ekranı sadece değişen kişiyi günceller, kod karıştırma, Firebase Crashlytics, Play paketi (AAB) + Google Play uygulama içi güncelleme, web'den hesap silme sayfası, gizlilik politikası güncellendi. Ayrıntı: [docs/PLAY_STORE.md](docs/PLAY_STORE.md).
* **Derleme 3:** Kaza kayıtlarını sıfırlama (iki aşamalı onay). Ayarlar'da "Anlık bildirim: Hazır ✓" durumu ve tekrar deneme; sunucu anahtarı etkinleştirildi.
* **Derleme 2:** Aile bildirimleri uygulama kapalıyken de (Firebase Cloud Messaging). Konum her açılışta otomatik (10 sn arayla tekrar deneme); konum sadece Ayarlar'da.
* Vakit hatırlatması **11 dk önce** + her bildirimde hadis/dua/özlü söz.
* Aile Reisi simgesi **🏡** (taç simgesi kaldırıldı), **başörtülü** simgeler.
* Sürüm açıklamalarında teknik ayrıntılar.

<details>
<summary>Geliştirme geçmişi (v1.0 öncesi test derlemeleri)</summary>

* **Derleme 36:** Temiz başlangıç (test önbelleği bir kez temizlenir), Öneri Yaz mail ile, vakitler yüklenmeden işaretleme kilitli, matriste boş vakitler "—".
* **Derleme 32:** Paylaşım penceresi (uygulama + davet kodu), ince çizgili vakit simgeleri.
* **Derleme 27:** Eski tasarım geri döndü; Hoş Geldiniz penceresi; gezinti modu; EMB kodları; 5 dk onay; Bağlantıyı Teyit Et; çevrimdışı kuyruk; aile bildirimleri; hesap silme; Kaza/Karne/Ayarlar yenilendi.
* **Derleme 21:** Herkese otomatik havuz ve kod; ünvanları reis verir.
* **Derleme 17:** Gizlilik: e-postalar gizlendi, commit geçmişi temizlendi; ayrıntılı README.
* **Derleme 16:** Aile Havuzu eski tasarım + v1.13–v1.18 revizeleri.
* **Derleme 13:** Eski uygulamanın tüm yapısı (GPS, Kıble, Karne, bildirimler).
* **Derleme 10:** Uygulama içi güncelleme.
* **Derleme 9:** Çam yeşili tasarım.
* **Derleme 6–8:** Telefondan hesap seçerek Google girişi.
* **Derleme 2:** İlk Flutter sürümü.
</details>
