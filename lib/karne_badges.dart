import 'package:intl/intl.dart' show DateFormat;

import 'dini_gunler.dart';
import 'models.dart';

/// Karne rozeti. [tiers] varsa seviyeli rozettir (Bronz / Gümüş / Altın / Elmas).
class KarneBadge {
  final String id, emoji, title, desc;
  final int value;
  final int target; // seviyesiz rozette hedef; seviyelide bir sonraki seviyenin hedefi
  final List<int>? tiers;
  final bool seasonal; // mübarek gün rozeti (yalnızca o dönem gelince görünür)
  const KarneBadge(this.id, this.emoji, this.title, this.desc, this.value, this.target,
      {this.tiers, this.seasonal = false});

  static const tierNames = ['Bronz', 'Gümüş', 'Altın', 'Elmas'];

  /// Ulaşılan seviye sayısı (seviyesiz rozette 0 ya da 1).
  int get level {
    final t = tiers;
    if (t == null) return value >= target ? 1 : 0;
    return t.where((x) => value >= x).length;
  }

  bool get earned => level > 0;
  bool get maxed => tiers == null ? earned : level == tiers!.length;

  /// Bir sonraki hedef (seviyelide sıradaki seviye).
  int get nextTarget => tiers == null ? target : (maxed ? tiers!.last : tiers![level]);

  String get levelName => tiers == null ? '' : (level == 0 ? '' : tierNames[level - 1]);

  /// Rozet kaydı için anahtar: seviyeli rozette her seviye ayrı kazanılır.
  String get key => tiers == null ? id : '$id:$level';
}

/// Kişinin kendi kayıtlarından rozetleri hesaplar (aile verisi kullanılmaz).
class KarneBadges {
  final Map<String, Map<String, PrayerStatus>> data; // yyyy-MM-dd → vakit durumları
  final int kazaOwed, kazaDone;
  final DateTime today;

  KarneBadges(this.data, this.kazaOwed, this.kazaDone, {DateTime? now})
      : today = DateTime((now ?? DateTime.now()).year, (now ?? DateTime.now()).month, (now ?? DateTime.now()).day);

  static final _f = DateFormat('yyyy-MM-dd');
  PrayerStatus _st(DateTime d, String k) => data[_f.format(d)]?[k] ?? PrayerStatus.none;
  bool _ok(DateTime d, String k) => _st(d, k) == PrayerStatus.prayed || _st(d, k) == PrayerStatus.excused;
  bool _marked(DateTime d) => prayerKeys.any((k) => _st(d, k) != PrayerStatus.none);

  bool fullDay(DateTime d) => prayerKeys.every((k) => _ok(d, k)) && prayerKeys.any((k) => _st(d, k) == PrayerStatus.prayed);

  DateTime _ago(int i) => today.subtract(Duration(days: i));

  /// En uzun ardışık gün serisi (son [span] gün içinde).
  int _best(bool Function(DateTime) ok, {int span = 400}) {
    var best = 0, run = 0;
    for (var i = span - 1; i >= 0; i--) {
      if (ok(_ago(i))) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return best;
  }

  /// Ardışık Cumalarda Cuma (öğle) namazı: en uzun seri.
  int _bestFridays() {
    var d = today;
    while (d.weekday != DateTime.friday) {
      d = d.subtract(const Duration(days: 1));
    }
    var best = 0, run = 0;
    final fridays = <DateTime>[];
    for (var i = 0; i < 57; i++) {
      fridays.add(d.subtract(Duration(days: 7 * i)));
    }
    for (final f in fridays.reversed) {
      if (_st(f, 'dhuhr') == PrayerStatus.prayed) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return best;
  }

  /// Yeniden Başlangıç: en az 3 gün aradan sonra 7 gün üst üste 5 vakit.
  bool _comeback() {
    var everMarked = false, gap = 0, run = 0, gapBefore = 0;
    for (var i = 399; i >= 0; i--) {
      final d = _ago(i);
      if (fullDay(d)) {
        if (run == 0) gapBefore = gap;
        run++;
        gap = 0;
        if (run >= 7 && gapBefore >= 3 && everMarked) return true;
        everMarked = true;
      } else {
        if (_marked(d)) everMarked = true;
        run = 0;
        gap++;
      }
    }
    return false;
  }

  (int prayed, int total) _score(DateTime from, DateTime to) {
    var p = 0, t = 0;
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      for (final k in prayerKeys) {
        final s = _st(d, k);
        if (s == PrayerStatus.excused) continue;
        t++;
        if (s == PrayerStatus.prayed) p++;
      }
    }
    return (p, t);
  }

  DateTime? _latest(String key) {
    final list = DiniGunler.events.where((e) => e.gun.key == key && !e.date.isAfter(today)).toList();
    if (list.isEmpty) return null;
    final d = list.last.date;
    return today.difference(d).inDays <= 400 ? d : null;
  }

  List<KarneBadge> all() {
    final week = [for (var i = 6; i >= 0; i--) _ago(i)];
    final fajrWeek = week.where((d) => _st(d, 'fajr') == PrayerStatus.prayed).length;
    final (wp, wt) = _score(week.first, today);
    final weekPct = wt == 0 ? 0 : (wp * 100 / wt).round();
    final bestFull = _best(fullDay);
    final out = <KarneBadge>[
      KarneBadge('fajr_week', '🌅', 'Sabah Namazı Muhafızı', 'Son 7 günün en az 5\'inde sabah namazı', fajrWeek, 5),
      KarneBadge('fivefive', '🏆', '5\'te 5 Sadakati', 'Bir günün 5 vaktini eksiksiz kıl', bestFull >= 1 ? 1 : 0, 1),
      KarneBadge('streak', '🔥', 'Namaz Serisi', 'Üst üste 5 vakit: 7 / 30 / 100 / 365 gün', bestFull, 7,
          tiers: const [7, 30, 100, 365]),
      KarneBadge('fajr40', '☀️', 'Sabah Serisi', 'Üst üste sabah namazı: 7 / 21 / 40 gün',
          _best((d) => _st(d, 'fajr') == PrayerStatus.prayed), 7,
          tiers: const [7, 21, 40]),
      KarneBadge('isha', '🌌', 'Yatsı Nöbetçisi', '14 gün kesintisiz yatsı namazı', _best((d) => _ok(d, 'isha') && _st(d, 'isha') != PrayerStatus.none), 14),
      KarneBadge('friday', '🕌', 'Cuma Sadığı', '4 Cuma üst üste Cuma namazı', _bestFridays(), 4),
      KarneBadge('steady', '⭐', 'İstikrar Yıldızı', 'Haftalık başarı %80 ve üzeri', weekPct, 80),
      KarneBadge('comeback', '🌱', 'Yeniden Başlangıç', 'Ara verdikten sonra 7 gün üst üste 5 vakit', _comeback() ? 1 : 0, 1),
      KarneBadge('kaza', '📿', 'Kaza Avcısı', 'Eda edilen kaza: 10 / 100 / 500 / 1000', kazaDone, 10,
          tiers: const [10, 100, 500, 1000]),
      if (kazaOwed > 0)
        KarneBadge('kaza_done', '🤲', 'Borçsuz Kul', 'Kaza borcunu tamamen bitir', kazaDone >= kazaOwed ? 1 : 0, 1),
    ];

    // ---- Mübarek gün rozetleri: yalnızca o dönem gelince görünür ----
    final ram = _latest('ramazan');
    if (ram != null) {
      final bayram = DiniGunler.events
          .where((e) => e.gun.key == 'ramazan_bayrami' && e.date.isAfter(ram))
          .map((e) => e.date)
          .firstOrNull;
      final end0 = (bayram ?? ram.add(const Duration(days: 30))).subtract(const Duration(days: 1));
      final end = end0.isAfter(today) ? today : end0;
      final total = end.difference(ram).inDays + 1;
      var full = 0;
      for (var d = ram; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        if (fullDay(d)) full++;
      }
      final days = end0.difference(ram).inDays + 1;
      out.add(KarneBadge('ramazan_${ram.year}', '🌙', 'Ramazan Rozeti',
          'Ramazan boyunca her gün 5 vakit ($total/$days gün geçti)', full, days, seasonal: true));
    }
    final kandils = DiniGunler.events
        .where((e) => const {'regaib', 'mirac', 'berat', 'mevlid', 'kadir'}.contains(e.gun.key) &&
            !e.date.isAfter(today) &&
            today.difference(e.date).inDays <= 400)
        .toList();
    if (kandils.isNotEmpty) {
      final got = kandils.where((e) => fullDay(e.date)).length;
      out.add(KarneBadge('kandil', '🕯️', 'Kandil Gecesi', 'Bir kandil gününde 5 vakit (${kandils.last.gun.name})', got, 1,
          seasonal: true));
    }
    final bayramlar = DiniGunler.events
        .where((e) => e.gun.bayram && !e.date.isAfter(today) && today.difference(e.date).inDays <= 400)
        .toList();
    if (bayramlar.isNotEmpty) {
      final got = bayramlar.where((e) => _st(e.date, 'fajr') == PrayerStatus.prayed).length;
      out.add(KarneBadge('bayram', '🎉', 'Bayram Sabahı', 'Bayram günü sabah namazı', got, 1, seasonal: true));
    }
    final uc = _latest('uc_aylar');
    if (uc != null) {
      final arefe = DiniGunler.events
          .where((e) => e.gun.key == 'ramazan_arefe' && e.date.isAfter(uc))
          .map((e) => e.date)
          .firstOrNull;
      final end0 = arefe ?? uc.add(const Duration(days: 88));
      final end = end0.isAfter(today) ? today : end0;
      final (p, t) = _score(uc, end);
      final pct = t == 0 ? 0 : (p * 100 / t).round();
      out.add(KarneBadge('uc_aylar_${uc.year}', '🌿', 'Üç Aylar Yolcusu', 'Üç aylar boyunca başarı %90 ve üzeri', pct, 90,
          seasonal: true));
    }
    return out;
  }

}
