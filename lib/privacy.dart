// Hata metinlerinden kişisel ve gizli bilgiyi silme (sunucuya, telefondaki kayda ya da maile gitmeden önce).
// Saf fonksiyon: birim testleriyle sınanır (test/privacy_test.dart).

final List<(RegExp, String)> _rules = [
  // Oturum anahtarları (JWT) ve "Bearer …" başlıkları
  (RegExp(r'eyJ[A-Za-z0-9_\-]{5,}(\.[A-Za-z0-9_\-]+){0,2}'), '[token]'),
  (RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false), 'Bearer [token]'),
  // Adres ve gövde içindeki gizli parametreler: access_token=…, apikey: …, "password":"…"
  (
    RegExp(
      r'''\b((?:access|refresh|id)_token|token|api_?key|apikey|secret|password|passwd|signature|authorization)(["']?\s*[=:]\s*["']?)[^\s&"',;}]+''',
      caseSensitive: false,
    ),
    r'$1$2[gizli]'
  ),
  // Adresteki tek kullanımlık giriş kodu (?code=…). Hata kodu ("code: 23514") korunur.
  (RegExp(r'([?&]code=)[^\s&]+'), r'$1[gizli]'),
  // E-posta
  (RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)+'), '[e-posta]'),
  // Kullanıcı / havuz kimlikleri (uuid)
  (RegExp(r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b'), '[kimlik]'),
  // Telefon numarası (Türkiye cep)
  (RegExp(r'(?<![\d])(?:\+?90[\s\-]?)?0?5\d{2}[\s\-]?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}(?![\d])'), '[telefon]'),
  // Veritabanı hata ayrıntısı satırın değerlerini yazar (ad, aile adı, dua metni olabilir):
  // "Failing row contains (…)" ve "Key (sütun)=(değer)" → satır sonuna kadar silinir (fail-closed:
  // değerin içindeki ":)" ya da iç içe parantez sızıntıya yol açmasın). Sütun adı kalır.
  (RegExp(r'(Failing row contains ).*'), r'$1([gizli])'),
  (RegExp(r'(Key \((?:[^()]|\([^()]*\))*\)=).*'), r'$1([gizli])'),
  // Uygulamanın telefondaki klasörü (/data/user/0/…, /data/data/…): klasör kökü kalır, devamı silinir
  (RegExp(r'''(/data/(?:user/\d+|data|user_de/\d+))/[^\s:)'"]+'''), r'$1/[uygulama]'),
  // Ortak depolamadaki dosya adları (indirilenler, fotoğraflar): klasör kalır, dosya adı silinir
  (RegExp(r'''(/storage/emulated/\d+|/sdcard)/[^\s:)'"]+'''), r'$1/[dosya]'),
  // Uzun anahtar benzeri diziler (bildirim jetonu, imza vb.)
  (RegExp(r'[A-Za-z0-9_\-:]{40,}'), '[gizli]'),
];

// Kişi adları genel bir kalıpla bulunamaz: uygulamanın bildiği adlar (kendi adı, aile üyeleri,
// katılım isteği gönderenler) yüklendikçe buraya eklenir ve hata metninde geçerse silinir.
final Map<String, List<RegExp>> _knownNames = {};

/// Ad ve soyad parçalarını hatırlar (3 harften kısa parçalar alınmaz: "Ali" alınır, "de" alınmaz).
void rememberNames(Iterable<String?> names) {
  for (final n in names) {
    for (final part in (n ?? '').trim().split(RegExp(r'\s+'))) {
      if (part.runes.length < 3 || _knownNames.containsKey(part)) continue;
      // Büyük/küçük harf ve Türkçe İ/ı farkı gözetilmez; yalnızca tam kelime olarak geçtiyse silinir.
      // Kalıplar bir kez derlenir (her hata metninde yeniden derlenmez).
      _knownNames[part] = {part, _trLower(part), _trUpper(part)}
          .map((v) => RegExp('(?<!\\p{L})${RegExp.escape(v)}(?!\\p{L})', caseSensitive: false, unicode: true))
          .toList();
    }
  }
}

/// Testler ve hesap değişimi için: hatırlanan adları temizler.
void forgetNames() => _knownNames.clear();

/// Metindeki e-posta, oturum anahtarı, kimlik, telefon, gizli parametre, dosya adı ve bilinen kişi
/// adlarını maskeler.
String scrubSensitive(String text) {
  var s = text;
  for (final (re, rep) in _rules) {
    s = s.replaceAllMapped(re, (m) => _expand(rep, m));
  }
  for (final res in _knownNames.values) {
    for (final re in res) {
      s = s.replaceAll(re, '[ad]');
    }
  }
  return s;
}

String _trLower(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
String _trUpper(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

String _expand(String rep, Match m) =>
    rep.replaceAllMapped(RegExp(r'\$(\d)'), (g) => m.group(int.parse(g.group(1)!)) ?? '');
