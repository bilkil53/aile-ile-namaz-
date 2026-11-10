import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'lang.dart';
import 'local_store.dart';
import 'models.dart';
import 'notifications.dart';
import 'settings.dart';

/// "5 vaktin hepsini kıldın" teşvik bildirimi: bugünün beş vakti de "Kıldı" işaretlenince kişinin
/// kendi telefonunda bir kez gösterilir. Aile üyelerine giden bildirimi sunucu üretir
/// (daily_prayers tetikleyicisi, ALL_PRAYED) — bu sınıf aileye bir şey göndermez.
class AllPrayed {
  static const _kSent = 'allPrayed.sent'; // "hesap|gün" — bildirimi gösterilmiş günler
  static Timer? _timer;

  /// Muaf günler sayılmaz: beş vaktin hepsi "Kıldı" olmalı.
  @visibleForTesting
  static bool isComplete(Map<String, PrayerStatus> day) =>
      prayerKeys.every((k) => day[k] == PrayerStatus.prayed);

  /// Bir vakit işaretlenince çağrılır. 3 sn bekler (hızlı değiştirmeler için), son duruma bakar.
  static void onMarked({required String uid, required String day, required String today, required PrayerStatus status}) {
    if (day != today || status != PrayerStatus.prayed) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      _timer = null;
      unawaited(_check(uid, day));
    });
  }

  static Future<void> _check(String uid, String day) async {
    try {
      if (!isComplete(LocalStore.day(day))) return;
      final id = '$uid|$day';
      final sent = AppSettings.prefs.getStringList(_kSent) ?? [];
      if (sent.contains(id)) return;
      // Önce kaydet: bildirim gösterilirken uygulama kapanırsa ikinci kez gösterilmesin
      await AppSettings.prefs.setStringList(_kSent, [...sent.skip(sent.length > 20 ? sent.length - 20 : 0), id]);
      await Notifications.showSpecial(
        8700,
        t('Maşallah! 5 vaktin hepsini kıldın 🌟', 'Masha\'Allah! You prayed all 5 prayers 🌟'),
        t('Bugünün bütün namazlarını eda ettin. Allah kabul etsin, istikrarını daim eylesin.',
            'You completed all of today\'s prayers. May Allah accept them and keep you steadfast.'),
      );
    } catch (_) {}
  }
}
