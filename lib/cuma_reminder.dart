import 'dart:async';

import 'package:intl/intl.dart' show DateFormat;

import 'content/content_en.dart';
import 'data.dart';
import 'lang.dart';
import 'local_store.dart';
import 'models.dart';
import 'notifications.dart';
import 'settings.dart';

/// Cuma uyarısı: erkek kullanıcı peş peşe 3 Cuma'nın Öğle (Cuma) namazını
/// "Kılmadı" işaretlerse kendisine özel bir hatırlatma gider; zincir sürdükçe
/// her Cuma yeniden (metinler sırayla değişir). Aileye gitmez. Demo'da gönderilmez.
/// Boş bırakılan / muaf / kılındı işaretli bir Cuma zinciri bozar.
class CumaReminder {
  static const _kGender = 'cuma.myGender';
  static const _kSent = 'cuma.sent'; // bildirimi giden Cuma tarihleri

  static const _texts = [
    (
      'Kim önemsemeyerek üç cumayı terk ederse, Allah onun kalbini mühürler.',
      'Ebû Dâvûd, Salât 210 · Tirmizî, Cum\'a 7 · Nesâî, Cum\'a 2',
    ),
    (
      'İnsanlar ya cumaları terk etmekten vazgeçerler ya da Allah onların kalplerini mühürler, sonra gafillerden olurlar.',
      'Müslim, Cum\'a 40',
    ),
    (
      'Beş vakit namaz ve cumadan cumaya kılınan namaz, büyük günahlardan kaçınıldıkça aralarındaki günahlara kefarettir.',
      'Müslim, Tahâret 14',
    ),
  ];

  static final Map<String, Timer> _timers = {};

  /// Bilinen cinsiyeti hafızada tut (reis ünvan verince belirlenir; tek kalınca da geçerli).
  static Future<void> rememberGender(String? g) async {
    if (g == 'm' || g == 'f') await AppSettings.prefs.setString(_kGender, g!);
  }

  /// Bir vakit işaretlenince çağrılır. 15 sn bekler (hızlı değiştirmeler için), son duruma bakar.
  static void onMarked(String day, String key, PrayerStatus status) {
    if (key != 'dhuhr') return;
    final d = DateTime.tryParse(day);
    if (d == null || d.weekday != DateTime.friday) return;
    _timers.remove(day)?.cancel();
    if (status != PrayerStatus.missed) return;
    _timers[day] = Timer(const Duration(seconds: 15), () {
      _timers.remove(day);
      unawaited(_check(day));
    });
  }

  static Future<void> _check(String day) async {
    try {
      if (LocalStore.day(day)['dhuhr'] != PrayerStatus.missed) return;
      final sent = AppSettings.prefs.getStringList(_kSent) ?? [];
      if (sent.contains(day)) return;

      // Cinsiyet: önce havuzdaki güncel bilgi, yoksa hafızadaki
      final me = await Repo.myMember();
      if (me != null) await rememberGender(genderOf(me));
      if (AppSettings.prefs.getString(_kGender) != 'm') return;

      final count = await _missedFridaysInARow(DateTime.parse(day));
      if (count < 3) return;

      final (hadisTr, kaynakTr) = _texts[(count - 3) % _texts.length];
      final hadis = tc(hadisTr), kaynak = tc(kaynakTr);
      await Notifications.showSpecial(
        8800 + DateTime.parse(day).day,
        t('🕌 Cuma namazı hatırlatması', '🕌 Friday prayer reminder'),
        t('$count Cumadır Cuma namazı kılınmadı.\n\n“$hadis”\n— $kaynak\n\nRabbim bir sonraki Cuma\'yı nasip etsin. 🤲',
            'Friday prayer has been missed for $count Fridays.\n\n“$hadis”\n— $kaynak\n\nMay Allah grant you the next Friday. 🤲'),
      );
      await AppSettings.prefs.setStringList(_kSent, [...sent.where((s) => s.compareTo(_ago(day, 400)) > 0), day]);
    } catch (_) {}
  }

  static String _ago(String day, int days) =>
      DateFormat('yyyy-MM-dd').format(DateTime.parse(day).subtract(Duration(days: days)));

  /// Bu Cuma'dan geriye doğru, Öğle'si "Kılmadı" olan peş peşe Cuma sayısı.
  static Future<int> _missedFridaysInARow(DateTime friday) async {
    final f = DateFormat('yyyy-MM-dd');
    final from = friday.subtract(const Duration(days: 7 * 26));
    Map<String, Map<String, PrayerStatus>> cloud = {};
    try {
      cloud = await Repo.myRange(from, friday).timeout(const Duration(seconds: 8));
    } catch (_) {}
    var count = 0;
    for (var d = friday; !d.isBefore(from); d = d.subtract(const Duration(days: 7))) {
      final key = f.format(d);
      // Telefondaki kayıt (henüz buluta gitmemiş olabilir) önceliklidir
      final s = LocalStore.day(key)['dhuhr'] ?? cloud[key]?['dhuhr'] ?? PrayerStatus.none;
      if (s != PrayerStatus.missed) break;
      count++;
    }
    return count;
  }
}
