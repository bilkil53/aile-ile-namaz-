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

  static bool get prayerReminders => _p.getBool('prayerReminders') ?? true;
  static Future<void> setPrayerReminders(bool v) => _p.setBool('prayerReminders', v);

  static bool get dailyContent => _p.getBool('dailyContent') ?? true;
  static Future<void> setDailyContent(bool v) => _p.setBool('dailyContent', v);

  static bool get familyAlerts => _p.getBool('familyAlerts') ?? true;
  static Future<void> setFamilyAlerts(bool v) => _p.setBool('familyAlerts', v);

  // Hangi aile bildirimlerini alayım? (cihaz başına; sunucu da buna göre gönderir)
  static bool get notifyPrayer => _p.getBool('notifyPrayer') ?? true;
  static bool get notifyKaza => _p.getBool('notifyKaza') ?? true;
  static bool get notifyDua => _p.getBool('notifyDua') ?? true;
  static bool get lockScreen => _p.getBool('lockScreen') ?? true;
  static Future<void> setNotify(String key, bool v) => _p.setBool(key, v);

  /// Cinsiyet ('m' erkek / 'f' kadın): "Muaf" seçeneği yalnızca kadınlarda gösterilir.
  static String? get gender => _p.getString('gender');
  static Future<void> setGender(String g) => _p.setString('gender', g);

  static int get reminderMinutes => _p.getInt('reminderMinutes') ?? 11;
}
