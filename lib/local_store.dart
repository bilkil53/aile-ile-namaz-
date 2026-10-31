import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'settings.dart';

/// Telefonda saklanan kayıtlar:
/// - Giriş yapmadan kullananların bütün verisi (misafir modu)
/// - Giriş yapanlar için son bilinen durum (çevrimdışı gösterim)
/// - İnternet yokken yapılan işlemlerin bekleme kuyruğu
class LocalStore {
  static String _pk(String date) => 'lp_$date';

  // ---- Misafir modu ----
  static bool get guestMode => AppSettings.prefs.getBool('guestMode') ?? false;
  static final guestChanged = ValueNotifier<int>(0);
  static Future<void> setGuestMode(bool v) async {
    await AppSettings.prefs.setBool('guestMode', v);
    guestChanged.value++;
  }

  /// Misafirken girilmiş ve henüz buluta taşınmamış veri var mı?
  static bool get hasGuestData => AppSettings.prefs.getBool('guestData') ?? false;
  static Future<void> setHasGuestData(bool v) => AppSettings.prefs.setBool('guestData', v);

  // ---- Günlük namaz ----
  static Map<String, PrayerStatus> day(String date) {
    final raw = AppSettings.prefs.getString(_pk(date));
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {for (final e in m.entries) e.key: PrayerStatusX.parse(e.value as String?)};
  }

  static Future<void> saveDay(String date, Map<String, PrayerStatus> m) =>
      AppSettings.prefs.setString(_pk(date), jsonEncode({for (final e in m.entries) e.key: e.value.code}));

  static Future<void> setPrayer(String date, String key, PrayerStatus s) async {
    final m = day(date);
    m[key] = s;
    await saveDay(date, m);
  }

  static List<String> allDates() => AppSettings.prefs
      .getKeys()
      .where((k) => k.startsWith('lp_'))
      .map((k) => k.substring(3))
      .toList()
    ..sort();

  // ---- Kaza ----
  static Map<String, (int, int)> kaza() {
    final raw = AppSettings.prefs.getString('lk');
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        e.key: (((e.value as List)[0] as num).toInt(), ((e.value as List)[1] as num).toInt()),
    };
  }

  static Future<void> saveKaza(String type, int owed, int done) async {
    final m = kaza();
    m[type] = (owed, done);
    await AppSettings.prefs.setString('lk', jsonEncode({for (final e in m.entries) e.key: [e.value.$1, e.value.$2]}));
  }

  // ---- Bekleme kuyruğu (çevrimdışı) ----
  static List<Map<String, dynamic>> queue() {
    final raw = AppSettings.prefs.getString('queue');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> saveQueue(List<Map<String, dynamic>> q) =>
      AppSettings.prefs.setString('queue', jsonEncode(q));

  static Future<void> enqueue(Map<String, dynamic> op) async {
    final q = queue();
    // Aynı vakit/kaza için eski kaydı en yenisiyle değiştir
    q.removeWhere((o) =>
        o['t'] == op['t'] &&
        ((op['t'] == 'prayer' && o['date'] == op['date'] && o['key'] == op['key']) ||
            (op['t'] == 'kaza' && o['type'] == op['type'])));
    q.add(op);
    await saveQueue(q);
  }

  static int get pendingCount => queue().length;
}
