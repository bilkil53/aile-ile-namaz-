import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'settings.dart';

/// Kayıtlar:
/// - Giriş yapmadan gezinenler (misafir): SADECE bellekte tutulur, uygulama kapanınca silinir.
///   Giriş yapılırsa o oturumda işaretlenenler buluta gönderilir.
/// - Giriş yapanlar için son bilinen durum (çevrimdışı gösterim) telefonda.
/// - İnternet yokken yapılan işlemlerin bekleme kuyruğu telefonda.
class LocalStore {
  static String _pk(String date) => 'lp_$date';

  /// Giriş yoksa kalıcı kayıt yapılmaz.
  static bool get _mem {
    try {
      return Supabase.instance.client.auth.currentUser == null;
    } catch (_) {
      return true; // istemci hazır değil: kalıcı yazma yapma (misafir gibi davran)
    }
  }

  // ---- Misafir (gezinti) modu: bellekte, her açılışta Hoş Geldiniz penceresi gelir ----
  static bool _guestMode = false;
  static bool get guestMode => _guestMode;
  static final guestChanged = ValueNotifier<int>(0);
  static Future<void> setGuestMode(bool v) async {
    _guestMode = v;
    guestChanged.value++;
  }

  static final Map<String, Map<String, PrayerStatus>> _gDays = {};
  static final Map<String, (int, int)> _gKaza = {};
  static bool _gData = false;

  /// Bu oturumda misafirken işaretlenmiş, henüz buluta gönderilmemiş veri var mı?
  static bool get hasGuestData => _gData;
  static Future<void> setHasGuestData(bool v) async => _gData = v;

  /// Misafir oturumunun verisi (giriş yapılınca buluta taşımak için), sonra temizlenir.
  static Map<String, Map<String, PrayerStatus>> get guestDays => _gDays;
  static Map<String, (int, int)> get guestKaza => _gKaza;
  static void clearGuest() {
    _gDays.clear();
    _gKaza.clear();
    _gData = false;
  }

  /// Eski sürümlerin kalıcı misafir bayraklarını ve test dönemi önbelleğini bir kez temizle.
  /// (Test sürümlerinde telefona yazılmış işaretler ve bekleyen kuyruk tekrar buluta gitmesin.)
  static Future<void> cleanupLegacy() async {
    final p = AppSettings.prefs;
    await p.remove('guestMode');
    await p.remove('guestData');
    if ((p.getInt('dataReset') ?? 0) < 1) {
      for (final k in p.getKeys().where((k) => k.startsWith('lp_')).toList()) {
        await p.remove(k);
      }
      await p.remove('lk');
      await p.remove('queue');
      await p.setInt('dataReset', 1);
    }
  }

  // ---- Günlük namaz ----
  static Map<String, PrayerStatus> day(String date) {
    if (_mem) return Map.of(_gDays[date] ?? const {});
    final raw = AppSettings.prefs.getString(_pk(date));
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {for (final e in m.entries) e.key: PrayerStatusX.parse(e.value as String?)};
  }

  static Future<void> saveDay(String date, Map<String, PrayerStatus> m) async {
    if (_mem) {
      _gDays[date] = Map.of(m);
      return;
    }
    await AppSettings.prefs.setString(_pk(date), jsonEncode({for (final e in m.entries) e.key: e.value.code}));
  }

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
    if (_mem) return Map.of(_gKaza);
    final raw = AppSettings.prefs.getString('lk');
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        e.key: (((e.value as List)[0] as num).toInt(), ((e.value as List)[1] as num).toInt()),
    };
  }

  static Future<void> saveKaza(String type, int owed, int done) async {
    if (_mem) {
      _gKaza[type] = (owed, done);
      return;
    }
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
