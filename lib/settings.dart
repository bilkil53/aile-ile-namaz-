import 'package:shared_preferences/shared_preferences.dart';

/// Cihazda saklanan ayarlar (konum, bildirim tercihleri).
class AppSettings {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static SharedPreferences get prefs => _p;

  static String get cityName => _p.getString('cityName') ?? 'İstanbul';
  static double get lat => _p.getDouble('lat') ?? 41.0082;
  static double get lng => _p.getDouble('lng') ?? 28.9784;
  static bool get locationFromGps => _p.getBool('locationFromGps') ?? false;

  static Future<void> setLocation(String name, double lat, double lng, {bool gps = false}) async {
    await _p.setString('cityName', name);
    await _p.setDouble('lat', lat);
    await _p.setDouble('lng', lng);
    await _p.setBool('locationFromGps', gps);
  }

  /// Vakit hatırlatması (11 dk önce) ve günün içeriği (12:00) zorunlu, kapatılamaz.
  static bool get prayerReminders => true;

  static bool get dailyContent => true;

  static bool get familyAlerts => _p.getBool('familyAlerts') ?? true;
  static Future<void> setFamilyAlerts(bool v) => _p.setBool('familyAlerts', v);

  // Hangi aile bildirimlerini alayım? (cihaz başına; sunucu da buna göre gönderir)
  static bool get notifyPrayer => _p.getBool('notifyPrayer') ?? true;
  static bool get notifyKaza => _p.getBool('notifyKaza') ?? true;
  static bool get notifyDua => _p.getBool('notifyDua') ?? true;
  // Varsayılan gizli: kilit ekranında yalnızca "yeni bildirim" görünür, ayrıntı kilit açılınca
  static bool get lockScreen => _p.getBool('lockScreen') ?? false;
  static Future<void> setNotify(String key, bool v) => _p.setBool(key, v);

  static int get reminderMinutes => _p.getInt('reminderMinutes') ?? 11;
}
