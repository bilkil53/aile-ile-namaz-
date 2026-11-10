# Google Play'e Yayın Rehberi (Aile İle Namaz)

Bu dosya Play Store'a çıkış günü yapılacakları ve hazır olanları listeler. Uygulama şu an GitHub'dan dağıtılıyor; Play paketi (AAB) her resmi yayında hazır üretiliyor.

## Hazır olanlar
| Konu | Durum |
|---|---|
| Uygulama paketi (AAB) | Her yayında `aile-ile-namaz.aab` (GitHub Releases + Actions artifact). Yükleme anahtarı = mevcut imza anahtarı. |
| Play güncellemesi | AAB `--dart-define=STORE=play` ile derlenir: GitHub APK indirme kapalı, Google Play uygulama içi güncelleme (in_app_update) açık. |
| APK kurma izni | AAB'de `REQUEST_INSTALL_PACKAGES` kaldırılır (Play politikası). |
| Hesap silme (uygulama içi) | Ayarlar → Hesabımı ve verilerimi sil |
| Hesap silme (web) | https://bilkil53.github.io/aile-ile-namaz-/delete-account.html |
| Gizlilik politikası | https://bilkil53.github.io/aile-ile-namaz-/privacy.html (İngilizce: privacy-en.html) |
| Kod karıştırma | `--obfuscate --split-debug-info` (sembol dosyaları Actions artifact'ında `debug-symbols.zip`) |
| Hedef Android sürümü | Flutter stable'ın varsayılanı (Play'in yıllık hedef SDK şartını karşılar); `flutter create` her derlemede günceller. |

## Çıkış günü yapılacaklar (sırayla)
0. **⚠️ KVKK yurt dışı aktarım:** Supabase ve Google ile Kurul'un standart sözleşmesi (Tip 2: veri sorumlusundan veri işleyene) Türkçe metin üzerinde imzalanmalı, imzadan itibaren 5 iş günü içinde Kurum'a bildirilmeli; ardından gizlilik sayfasındaki aktarım dayanağı cümlesi "standart sözleşme" olarak güncellenmeli. Bir KVKK avukatına danışılması önerilir.
1. **Play Console geliştirici hesabı** aç (tek seferlik 25 $), uygulama oluştur: ad "Aile İle Namaz", paket `com.bilkil53.aile_ile_namaz`.
2. **Play App Signing**'i kabul et; ilk sürüm olarak son `aile-ile-namaz.aab` dosyasını "Dahili test" kanalına yükle.
3. **⚠️ Google girişi (S2):** Play uygulamayı kendi anahtarıyla imzalar → SHA-1 değişir. Play Console → *Kurulum → Uygulama imzalama* sayfasındaki **"Uygulama imzalama anahtarı sertifikası" SHA-1**'ini kopyala ve şuralara ekle:
   - Google Cloud **aile-ile-namaz-513220** → APIs & Services → Credentials → *Aile ile Namaz Android* OAuth istemcisi. (Paket adı aynı, SHA-1 Play'inki olan **ikinci bir Android istemcisi** oluştur; mevcut olanı silme — GitHub APK'sı onu kullanıyor.)
   - Firebase **aile-ile-namaz-d437f** → Proje ayarları → Android uygulaması → *Parmak izi ekle*.
   - Google Cloud **aile-ile-namaz-d437f** → Credentials → *Android key (auto created by Firebase)* → Android uygulama kısıtlamasına aynı paket + Play SHA-1'ini ekle.
4. **Veri güvenliği formu** (Data safety):
   - Toplanan: Ad, e-posta (hesap yönetimi) · Uygulama etkinliği: namaz/kaza kayıtları, mesajlar (uygulama işlevi) · Cihaz kimliği: bildirim kimliği (uygulama işlevi) · Uygulama bilgileri ve performansı: çökme/hata raporu — **isteğe bağlı** (yalnızca kullanıcı "Raporu gönder" derse; hesapla ilişkilendirilmez; uygulama işlevi/hata giderme)
   - Konum: **yaklaşık konum paylaşılıyor, toplanmıyor** — yaklaşık 1 km'ye yuvarlanmış koordinat, kimlik bilgisi olmadan namaz vakti servisine (api.aladhan.com) gönderilir; sunucumuzda saklanmaz. Play formunda "Yaklaşık konum → uygulama işlevi → geçici işleme" olarak beyan edilir.
   - Veriler aktarım sırasında şifreleniyor: Evet · Kullanıcı silme isteyebilir: Evet (uygulama içi + web bağlantısı).
   - Üçüncü taraflarla paylaşım: yalnızca yaklaşık konum (namaz vakti servisi api.aladhan.com); diğer veriler için Hayır (Supabase ve Firebase hizmet sağlayıcıdır).
5. **İzin beyanları:** Konum (ön planda, vakit hesabı); Bildirim; Kesin alarm (`SCHEDULE_EXACT_ALARM` — namaz vakti hatırlatıcısı, kullanıcı izniyle).
6. **İçerik derecelendirmesi** anketi (dini içerik, şiddet yok) → genellikle "Herkes".
7. **Mağaza sayfası:** kısa/uzun açıklama, en az 2 ekran görüntüsü, 512×512 simge, 1024×500 öne çıkan görsel.
8. Dahili test → kapalı test (Play yeni bireysel hesaplarda 12 test kullanıcısı / 14 gün şartı arayabilir) → üretim.

## Mağaza metni (taslak)
**Kısa açıklama (80 karakter):**
Ailece namaz takibi: vakitler, aile havuzu, kaza takibi, karne ve hatırlatmalar.

**Uzun açıklama:**
Aile İle Namaz, namazlarınızı ailenizle birlikte takip etmeniz için hazırlandı.

• Diyanet uyumlu namaz vakitleri ve vakit hatırlatmaları
• Aile Havuzu: en fazla 5 kişilik ailenizle kim hangi vakti kıldı, birlikte görün; birbirinize dua gönderin
• Kaza namazı takibi: borcunuzu kaydedin, kıldıkça düşün
• Karne: seri, aylık takvim, istatistikler ve manevi rozetler
• Mübarek gün ve gece hatırlatmaları, Cuma hatırlatması
• Reklamsız ve sade; Türkçe ve İngilizce

👨‍👩‍👧 Aile Pro'su: Aile Reisinin Pro alması yeterli; aile havuzundaki herkes (en fazla 5 kişi) Pro olur. Her yeni kullanıcıya 7 gün ücretsiz deneme.
Fiyat: aylık 153 ₺ · yıllık 1.553 ₺ (Google Play üzerinden, otomatik yenilenir; Google Play aboneliklerinden istediğiniz zaman iptal edebilirsiniz).

ℹ️ Hizmet notu: Aile havuzu, aile bildirimleri, bulut yedekleme ve Pro gibi internet gerektiren özellikler, uygulamanın sunucu altyapısı (Supabase, Google Firebase) çalıştığı sürece kullanılabilir. Bakım veya altyapı kesintilerinde bu özellikler geçici olarak çalışmayabilir. Namaz vakitleri ve telefona kaydedilen işaretler internetsiz de çalışır; bağlantı gelince otomatik eşitlenir.

## Ücretsiz plandan çıkış
- Supabase ücretsiz proje **7 gün hiç kullanılmazsa duraklatılır**; aktif kullanıcılarla sorun olmaz. Büyüyünce Pro (25 $/ay) — kod değişikliği gerekmez.
- Test ve gerçek ortam ayrılmak istenirse: yeni Supabase projesi + derlemede `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_PUBLISHABLE_KEY=…` (kod hazır).
