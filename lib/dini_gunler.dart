import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

import 'settings.dart';

/// Mübarek gün tanımı. Tarihler Diyanet hicri takviminden (aladhan calendarMethod=DIYANET)
/// her yıl otomatik alınır; Diyanet'in yayımladığı dini günler listesiyle aynıdır.
class DiniGun {
  final String key;
  final String name;
  final String emoji;
  final bool bayram;

  /// Bayram kaç gün sürer (bayram değilse 1).
  final int days;

  /// Hicri (gün, ay). Kandiller bir önceki akşam idrak edildiği için [eveBefore] = true
  /// (tarih 1 gün geri alınır, bildirimde "Yarın akşam" denir). [dayBefore]: tarih 1 gün geri
  /// alınır ama gündüz idrak edilir (Ramazan Bayramı arefesi = Ramazan'ın son günü).
  final int hDay, hMonth;
  final bool eveBefore, dayBefore;

  /// Regaib: Recep'in ilk Cuma gecesi (hesaplanır).
  final bool regaib;

  /// Bildirimde ve kartta gösterilecek açıklama (kendi cümlelerimizle).
  final String meaning;

  const DiniGun(this.key, this.name, this.emoji, this.hDay, this.hMonth, this.meaning,
      {this.eveBefore = false, this.dayBefore = false, this.bayram = false, this.days = 1, this.regaib = false});
}

const diniGunler = <DiniGun>[
  DiniGun('hicri_yilbasi', 'Hicri Yılbaşı', '🌙', 1, 1,
      'Hz. Peygamber\'in (s.a.s.) Mekke\'den Medine\'ye hicretiyle başlayan hicri takvimde yeni bir yıl. '
      'Geçen yılın muhasebesini yapıp yeni yıla tövbe, dua ve güzel niyetlerle başlamak için bir fırsat.'),
  DiniGun('asure', 'Aşure Günü', '🥣', 10, 1,
      'Muharrem ayının onuncu günü. Peygamber Efendimiz bu gün oruç tutmuş ve tutulmasını tavsiye etmiştir; '
      'bir gün öncesi ya da sonrasıyla birlikte tutulması güzeldir. Aşure paylaşmak komşuluk ve kardeşliğin sembolüdür.'),
  DiniGun('mevlid', 'Mevlid Kandili', '🕯️', 12, 3,
      'Peygamber Efendimiz Hz. Muhammed\'in (s.a.s.) dünyaya teşrif ettiği gece. Onun hayatını, ahlakını ve '
      'sünnetini hatırlamak; salavat getirmek, Kur\'an okumak ve dua etmekle değerlendirilir.',
      eveBefore: true),
  DiniGun('uc_aylar', 'Üç Ayların Başlangıcı', '🌿', 1, 7,
      'Recep, Şaban ve Ramazan aylarından oluşan mübarek üç aylar başlıyor. Efendimizin "Allah\'ım! Recep ve Şaban\'ı '
      'bize mübarek kıl ve bizi Ramazan\'a ulaştır" duası bu ayların ruhunu anlatır.'),
  DiniGun('regaib', 'Regaib Kandili', '🕯️', 1, 7,
      'Üç ayların ilk Cuma gecesi. "Regaib" çokça istenen, değerli şeyler demektir; Allah\'ın lütuf ve ikramının bol olduğu '
      'bu gece namaz, dua, tövbe ve Kur\'an ile ihya edilir.',
      eveBefore: true, regaib: true),
  DiniGun('mirac', 'Miraç Kandili', '🕯️', 27, 7,
      'Peygamber Efendimizin Mescid-i Haram\'dan Mescid-i Aksa\'ya, oradan da semaya yükseltildiği gece. '
      'Beş vakit namaz bu gecede farz kılındı; bu yüzden namazın değerini hatırlamak için özel bir gecedir.',
      eveBefore: true),
  DiniGun('berat', 'Berat Kandili', '🕯️', 15, 8,
      'Şaban ayının on beşinci gecesi. "Berat" kurtuluş ve aklanma demektir; günahlardan arınma, af dileme ve '
      'Ramazan\'a hazırlık gecesidir. Gündüzünde oruç tutmak tavsiye edilmiştir.',
      eveBefore: true),
  DiniGun('ramazan', 'Ramazan Başlangıcı', '🌙', 1, 9,
      'On bir ayın sultanı Ramazan başlıyor. Kur\'an\'ın indirildiği bu ayda oruç farzdır; teravih, mukabele, '
      'sadaka ve paylaşma ile değerlendirilir. İlk sahura bu gece kalkılır.'),
  DiniGun('kadir', 'Kadir Gecesi', '✨', 27, 9,
      'Kur\'an-ı Kerim\'in indirilmeye başlandığı ve Kadir Sûresi\'nde "bin aydan daha hayırlı" olduğu bildirilen gece. '
      'Namaz, Kur\'an, tövbe ve duayla ihya edilir.',
      eveBefore: true),
  DiniGun('ramazan_arefe', 'Ramazan Bayramı Arefesi', '🤲', 1, 10,
      'Ramazan\'ın son günü ve bayramın arifesi. Fitre ve zekâtı bayramdan önce ihtiyaç sahiplerine ulaştırmak, '
      'küskünlükleri bitirmek için güzel bir gün.',
      dayBefore: true),
  DiniGun('ramazan_bayrami', 'Ramazan Bayramı', '🎉', 1, 10,
      'Bir ay süren orucun ardından şükür bayramı. Bayram namazı kılınır, büyükler ziyaret edilir, küçükler sevindirilir; '
      'küsler barışır, kapılar ve gönüller açılır.',
      bayram: true, days: 3),
  DiniGun('kurban_arefe', 'Kurban Bayramı Arefesi', '🤲', 9, 12,
      'Hacıların Arafat\'ta vakfeye durduğu gün. Arefe günü oruç tutmak ve çokça dua etmek tavsiye edilmiştir; '
      'teşrik tekbirleri bu günün sabah namazından itibaren başlar.'),
  DiniGun('kurban_bayrami', 'Kurban Bayramı', '🐑', 10, 12,
      'Hz. İbrahim\'in teslimiyetini hatırlatan bayram. Kurban, Allah\'a yakınlaşmak ve paylaşmak için kesilir; '
      'eti akraba, komşu ve ihtiyaç sahipleriyle paylaşılır. Teşrik tekbirleri bayramın 4. günü ikindiye kadar sürer.',
      bayram: true, days: 4),
];

class DiniGunEvent {
  final DiniGun gun;
  final DateTime date; // Diyanet listesindeki gün (kandilde akşamı idrak edilen gün)
  const DiniGunEvent(this.gun, this.date);
}

/// Dini günler: Diyanet hicri takviminden yılda bir otomatik güncellenir ve ilerler.
/// Bu hicri yıl + sonraki hicri yıl önbellekte tutulur; liste bitmeye yaklaşınca yenilenir.
class DiniGunler {
  static const _kCache = 'diniGunler.v1';

  static List<DiniGunEvent> _events = [];
  static List<DiniGunEvent> get events => _events;

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  static void _load() {
    final raw = AppSettings.prefs.getString(_kCache);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final list = <DiniGunEvent>[];
      for (final e in (j['events'] as List)) {
        final g = diniGunler.where((x) => x.key == e['k']).firstOrNull;
        if (g != null) list.add(DiniGunEvent(g, DateTime.parse(e['d'] as String)));
      }
      list.sort((a, b) => a.date.compareTo(b.date));
      _events = list;
    } catch (_) {}
  }

  static DateTime? _fetchedAt() {
    final raw = AppSettings.prefs.getString(_kCache);
    if (raw == null) return null;
    try {
      return DateTime.tryParse((jsonDecode(raw) as Map<String, dynamic>)['at'] as String);
    } catch (_) {
      return null;
    }
  }

  /// Gerekirse (ilk açılış, ayda bir kontrol, liste 4 aydan az kaldıysa) Diyanet takviminden yeniler.
  static Future<void> ensure() async {
    if (_events.isEmpty) _load();
    final now = _d(DateTime.now());
    final last = _events.isEmpty ? null : _events.last.date;
    final at = _fetchedAt();
    final stale = at == null || now.difference(at).inDays > 30;
    final short = last == null || last.difference(now).inDays < 120;
    if (!stale && !short) return;
    try {
      final hYear = await _hijriYearOf(now);
      final list = <DiniGunEvent>[];
      for (final y in [hYear, hYear + 1]) {
        for (final g in diniGunler) {
          var day = await _hToG(g.hDay, g.hMonth, y);
          if (g.regaib) {
            // Recep içindeki ilk Cuma gecesi (Perşembe akşamı Recep'e düşmeli): Cuma ≥ 2 Recep
            day = day.add(const Duration(days: 1));
            while (day.weekday != DateTime.friday) {
              day = day.add(const Duration(days: 1));
            }
          }
          if (g.eveBefore || g.dayBefore) day = day.subtract(const Duration(days: 1));
          list.add(DiniGunEvent(g, day));
        }
      }
      list.sort((a, b) => a.date.compareTo(b.date));
      _events = list;
      await AppSettings.prefs.setString(
          _kCache,
          jsonEncode({
            'at': now.toIso8601String(),
            'events': [
              for (final e in list) {'k': e.gun.key, 'd': DateFormat('yyyy-MM-dd').format(e.date)}
            ],
          }));
    } catch (_) {
      // İnternet yoksa eldeki liste kullanılır; sonraki açılışta tekrar denenir.
    }
  }

  /// Bugün bayram mı? (gün, bayramın kaçıncı günü)
  static (DiniGun, int)? bayramOn(DateTime day) {
    final d = _d(day);
    for (final e in _events.where((e) => e.gun.bayram)) {
      final diff = d.difference(e.date).inDays;
      if (diff >= 0 && diff < e.gun.days) return (e.gun, diff + 1);
    }
    return null;
  }

  /// Bugün idrak edilen (bayram dışı) mübarek gün/gece.
  static DiniGun? specialOn(DateTime day) {
    final d = _d(day);
    return _events.where((e) => !e.gun.bayram && e.date == d).map((e) => e.gun).firstOrNull;
  }

  static Future<int> _hijriYearOf(DateTime d) async {
    final j = await _get('https://api.aladhan.com/v1/gToH/${DateFormat('dd-MM-yyyy').format(d)}?calendarMethod=DIYANET');
    return int.parse(((j['data'] as Map)['hijri'] as Map)['year'] as String);
  }

  static Future<DateTime> _hToG(int day, int month, int year) async {
    final h = '${day.toString().padLeft(2, '0')}-${month.toString().padLeft(2, '0')}-$year';
    final j = await _get('https://api.aladhan.com/v1/hToG/$h?calendarMethod=DIYANET');
    final g = ((j['data'] as Map)['gregorian'] as Map)['date'] as String; // dd-MM-yyyy
    return DateFormat('dd-MM-yyyy').parse(g);
  }

  static Future<Map<String, dynamic>> _get(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}
