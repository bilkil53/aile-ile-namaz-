import '../dini_gunler.dart';
import '../lang.dart';
import 'daily_content.dart';

/// Aileye gönderilen hazır mesajlar (Aile Havuzu tebrikleri, bayram tebriği) her zaman Türkçe
/// metniyle gönderilir. Alıcı kendi dilinde görür: uygulamada [familyMessageText], kapalıyken
/// gelen bildirimde push-family (sunucudaki GREET_EN listesi; test ikisinin aynı olduğunu denetler).
/// Eski sürümler zaten Türkçe olduğundan Türkçe metin onlarda da doğru görünür.

String bayramMessageTr(DiniGun g) =>
    '${g.emoji} ${g.nameTr}nız mübarek olsun! Allah nice bayramlara sağlık, huzur ve '
    'birlik içinde ulaştırsın. 🤲';

String bayramMessageEn(DiniGun g) =>
    '${g.emoji} ${g.nameEn} Mubarak! May Allah let us reach many more Eids in health, peace '
    'and togetherness. 🤲';

/// Türkçe hazır mesaj → İngilizcesi.
final Map<String, String> familyMessagesEn = {
  for (final g in greetings) g.textTr: g.textEn,
  for (final d in diniGunler.where((d) => d.bayram)) bayramMessageTr(d): bayramMessageEn(d),
};

/// İngilizce → Türkçe: 1.78 sürümü hazır mesajları gönderenin dilinde yolluyordu; İngilizce
/// kullanan birinin eski sürümden gönderdiği tebrik Türkçe alıcıda Türkçe görünsün.
final Map<String, String> familyMessagesTr = {for (final e in familyMessagesEn.entries) e.value: e.key};

/// Gelen aile mesajını alıcının dilinde döndürür; kendi yazılmış mesajlar olduğu gibi kalır.
String familyMessageText(String m) => (Lang.isEn ? familyMessagesEn[m] : familyMessagesTr[m]) ?? m;
