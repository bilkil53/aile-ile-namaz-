import '../dini_gunler.dart';
import '../lang.dart';
import 'daily_content.dart';

/// Aileye gönderilen hazır mesajlar (Aile Havuzu tebrikleri, bayram ve mübarek gün tebriği) her zaman Türkçe
/// metniyle gönderilir. Alıcı kendi dilinde görür: uygulamada [familyMessageText], kapalıyken
/// gelen bildirimde push-family (sunucudaki GREET_EN listesi; test ikisinin aynı olduğunu denetler).
/// Eski sürümler zaten Türkçe olduğundan Türkçe metin onlarda da doğru görünür.

String bayramMessageTr(DiniGun g) =>
    '${g.emoji} ${g.nameTr}nız mübarek olsun! Allah nice bayramlara sağlık, huzur ve '
    'birlik içinde ulaştırsın. 🤲';

String bayramMessageEn(DiniGun g) =>
    '${g.emoji} ${g.nameEn} Mubarak! May Allah let us reach many more Eids in health, peace '
    'and togetherness. 🤲';

/// Bayram dışındaki mübarek gün ve geceler için tebrik (anahtar → Türkçe, İngilizce).
const Map<String, (String, String)> _ozelGunTebrik = {
  'hicri_yilbasi': (
    '🌙 Hicri yeni yılınız mübarek olsun! Rabbim yeni yılı hayırlara vesile kılsın. 🤲',
    '🌙 Happy Islamic New Year! May my Lord make the new year a means of goodness. 🤲'),
  'asure': (
    '🥣 Aşure Gününüz mübarek olsun! Rabbim rahmetini ve bereketini üzerimizden eksik etmesin. 🤲',
    '🥣 Blessed Day of Ashura! May my Lord never withhold His mercy and blessings from us. 🤲'),
  'mevlid': (
    '🕯️ Mevlid Kandiliniz mübarek olsun! Rabbim dualarımızı kabul eylesin. 🤲',
    '🕯️ Blessed Mawlid Kandil! May my Lord accept our prayers. 🤲'),
  'uc_aylar': (
    '🌿 Üç Aylarınız mübarek olsun! Rabbim bu mübarek ayları hayırla idrak etmeyi nasip eylesin. 🤲',
    '🌿 Blessed Three Holy Months! May my Lord grant us to observe these blessed months in goodness. 🤲'),
  'regaib': (
    '🕯️ Regaib Kandiliniz mübarek olsun! Rabbim dualarımızı kabul eylesin. 🤲',
    '🕯️ Blessed Raghaib Kandil! May my Lord accept our prayers. 🤲'),
  'mirac': (
    '🕯️ Miraç Kandiliniz mübarek olsun! Rabbim dualarımızı kabul eylesin. 🤲',
    "🕯️ Blessed Mi'raj Kandil! May my Lord accept our prayers. 🤲"),
  'berat': (
    '🕯️ Berat Kandiliniz mübarek olsun! Rabbim dualarımızı kabul eylesin. 🤲',
    "🕯️ Blessed Bara'ah Kandil! May my Lord accept our prayers. 🤲"),
  'ramazan': (
    '🌙 Ramazan-ı Şerifiniz mübarek olsun! Rabbim oruçlarımızı ve ibadetlerimizi kabul eylesin. 🤲',
    '🌙 Ramadan Mubarak! May my Lord accept our fasts and worship. 🤲'),
  'kadir': (
    '✨ Kadir Geceniz mübarek olsun! Rabbim dualarımızı kabul eylesin. 🤲',
    '✨ Blessed Laylat al-Qadr! May my Lord accept our prayers. 🤲'),
  'ramazan_arefe': (
    '🤲 Ramazan Bayramı arefeniz mübarek olsun! Rabbim dualarımızı kabul eylesin.',
    '🤲 Blessed eve of Eid al-Fitr! May my Lord accept our prayers.'),
  'kurban_arefe': (
    '🤲 Arefe gününüz mübarek olsun! Rabbim dualarımızı kabul eylesin.',
    '🤲 Blessed Day of Arafah! May my Lord accept our prayers.'),
};

/// Mübarek gün tebriği (bayramda bayram tebriği). Aileye her zaman Türkçesi gider.
String diniGunMessageTr(DiniGun g) => g.bayram ? bayramMessageTr(g) : (_ozelGunTebrik[g.key]?.$1 ?? '${g.emoji} ${g.nameTr} mübarek olsun! 🤲');
String diniGunMessageEn(DiniGun g) => g.bayram ? bayramMessageEn(g) : (_ozelGunTebrik[g.key]?.$2 ?? '${g.emoji} Blessed ${g.nameEn}! 🤲');

/// Türkçe hazır mesaj → İngilizcesi.
final Map<String, String> familyMessagesEn = {
  for (final g in greetings) g.textTr: g.textEn,
  for (final d in diniGunler) diniGunMessageTr(d): diniGunMessageEn(d),
};

/// İngilizce → Türkçe: 1.78 sürümü hazır mesajları gönderenin dilinde yolluyordu; İngilizce
/// kullanan birinin eski sürümden gönderdiği tebrik Türkçe alıcıda Türkçe görünsün.
final Map<String, String> familyMessagesTr = {for (final e in familyMessagesEn.entries) e.value: e.key};

/// Gelen aile mesajını alıcının dilinde döndürür; kendi yazılmış mesajlar olduğu gibi kalır.
String familyMessageText(String m) => (Lang.isEn ? familyMessagesEn[m] : familyMessagesTr[m]) ?? m;
