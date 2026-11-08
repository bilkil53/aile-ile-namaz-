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
  // Ortak depolamadaki dosya adları (indirilenler, fotoğraflar): klasör kalır, dosya adı silinir
  (RegExp(r'''(/storage/emulated/\d+|/sdcard)/[^\s:)'"]+'''), r'$1/[dosya]'),
  // Uzun anahtar benzeri diziler (bildirim jetonu, imza vb.)
  (RegExp(r'[A-Za-z0-9_\-:]{40,}'), '[gizli]'),
];

/// Metindeki e-posta, oturum anahtarı, kimlik, telefon, gizli parametre ve dosya adlarını maskeler.
String scrubSensitive(String text) {
  var s = text;
  for (final (re, rep) in _rules) {
    s = s.replaceAllMapped(re, (m) => _expand(rep, m));
  }
  return s;
}

String _expand(String rep, Match m) =>
    rep.replaceAllMapped(RegExp(r'\$(\d)'), (g) => m.group(int.parse(g.group(1)!)) ?? '');
