# Aile İle Namaz (v2)

Aile havuzu ile namaz takibi. **Flutter** (Android + iOS) ve **Supabase** (giriş, veritabanı, canlı güncelleme).

## Özellikler (bu sürüm)
- Google (Gmail) ile giriş
- Aile havuzu oluşturma; her havuzu **tek bir yönetici** yönetir
- Davet koduyla katılma isteği, yönetici onayı
- Yönetici: onay/ret, üye çıkarma, davet kodunu yenileme, yöneticiliği devretme
- Günlük 5 vakit: Kıldım / Kılmadım / Muaf
- Aile tablosu, canlı olay akışı, dua gönderme
- Her aile birbirinden izole (veritabanı RLS kuralları)

## Henüz yok (sıradakiler)
- Kaza takibi ekranı (veritabanı hazır: `kaza_prayers`, `kaza_summary`)
- Diyanet namaz vakitleri, vakit hatırlatmaları, kıble pusulası
- Uygulama kapalıyken telefona push bildirim (FCM + Supabase Edge Function)

## Kurulum
1. Flutter'ı kur: <https://docs.flutter.dev/get-started/install>
2. Bu repoda platform klasörlerini oluştur (mevcut `lib/` ve `pubspec.yaml` korunur):
   ```
   flutter create . --org com.bilkil53 --project-name aile_ile_namaz --platforms android,ios
   flutter pub get
   ```
3. **Google ile giriş ayarı** (bir kerelik):
   - Google Cloud Console → OAuth istemcisi (Web application) oluştur.
     Yetkili yönlendirme URI'si: `https://tgshrnodnhmnofjhzpqp.supabase.co/auth/v1/callback`
   - Supabase panosu → Authentication → Providers → Google: Client ID ve Secret'ı gir.
   - Supabase → Authentication → URL Configuration → Redirect URLs listesine ekle:
     `io.supabase.aileilenamaz://login-callback/`
4. **Uygulamaya dönüş bağlantısı** (`android/app/src/main/AndroidManifest.xml`, `<activity>` içine):
   ```xml
   <intent-filter>
     <action android:name="android.intent.action.VIEW" />
     <category android:name="android.intent.category.DEFAULT" />
     <category android:name="android.intent.category.BROWSABLE" />
     <data android:scheme="io.supabase.aileilenamaz" android:host="login-callback" />
   </intent-filter>
   ```
   iOS için `ios/Runner/Info.plist` içine aynı şemayı `CFBundleURLTypes` olarak ekle.
5. Çalıştır: `flutter run`

## Güvenlik notları
- `lib/config.dart` içindeki anahtar **publishable** anahtardır; istemcide olması normaldir. Veri güvenliği
  Supabase'deki RLS kurallarıyla sağlanır. `service_role` anahtarını ASLA uygulamaya veya repoya koyma.
- Eski sürümün aksine havuz verisi herkese açık kanallarda dolaşmaz; üyelik ve yönetici onayı sunucuda doğrulanır.
- Veritabanı şemasını repoda sürümlemek için: `supabase db pull` (Supabase CLI).

## Veritabanı özeti
`profiles`, `pools` (owner_id = yönetici), `pool_members`, `join_requests`, `daily_prayers`,
`kaza_prayers` (sadece sahibi), `kaza_summary` (üyeler toplamı görür), `pool_events`, `devices`.
Sunucu fonksiyonları: `create_pool`, `request_join`, `approve_join`, `reject_join`, `leave_pool`,
`remove_member`, `transfer_ownership`, `regenerate_invite_code`.
