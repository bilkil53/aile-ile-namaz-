import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:intl/intl.dart' show DateFormat;

import 'settings.dart';

class City {
  final String name;
  final double lat, lng;
  const City(this.name, this.lat, this.lng);
}

/// 81 il (+ Mekke, Medine, Kudüs).
const turkeyCities = <City>[
  City('Adana', 37.0000, 35.3213), City('Adıyaman', 37.7648, 38.2786),
  City('Afyonkarahisar', 38.7569, 30.5387), City('Ağrı', 39.7191, 43.0503),
  City('Aksaray', 38.3687, 34.0370), City('Amasya', 40.6501, 35.8353),
  City('Ankara', 39.9334, 32.8597), City('Antalya', 36.8969, 30.7133),
  City('Ardahan', 41.1105, 42.7022), City('Artvin', 41.1828, 41.8183),
  City('Aydın', 37.8380, 27.8456), City('Balıkesir', 39.6484, 27.8826),
  City('Bartın', 41.6344, 32.3375), City('Batman', 37.8874, 41.1294),
  City('Bayburt', 40.2552, 40.2249), City('Bilecik', 40.1451, 29.9799),
  City('Bingöl', 38.8854, 40.4983), City('Bitlis', 38.4006, 42.1095),
  City('Bolu', 40.7350, 31.6061), City('Burdur', 37.7203, 30.2908),
  City('Bursa', 40.1885, 29.0610), City('Çanakkale', 40.1553, 26.4142),
  City('Çankırı', 40.6013, 33.6134), City('Çorum', 40.5489, 34.9537),
  City('Denizli', 37.7830, 29.0963), City('Diyarbakır', 37.9144, 40.2306),
  City('Düzce', 40.8438, 31.1565), City('Edirne', 41.6771, 26.5557),
  City('Elazığ', 38.6748, 39.2225), City('Erzincan', 39.7500, 39.5000),
  City('Erzurum', 39.9055, 41.2658), City('Eskişehir', 39.7767, 30.5206),
  City('Gaziantep', 37.0662, 37.3833), City('Giresun', 40.9175, 38.3927),
  City('Gümüşhane', 40.4600, 39.4814), City('Hakkari', 37.5833, 43.7333),
  City('Hatay', 36.2023, 36.1606), City('Iğdır', 39.9196, 44.0454),
  City('Isparta', 37.7648, 30.5566), City('İstanbul', 41.0082, 28.9784),
  City('İzmir', 38.4237, 27.1428), City('Kahramanmaraş', 37.5753, 36.9228),
  City('Karabük', 41.2061, 32.6204), City('Karaman', 37.1759, 33.2287),
  City('Kars', 40.6013, 43.0975), City('Kastamonu', 41.3887, 33.7827),
  City('Kayseri', 38.7205, 35.4826), City('Kilis', 36.7184, 37.1212),
  City('Kırıkkale', 39.8468, 33.5153), City('Kırklareli', 41.7333, 27.2167),
  City('Kırşehir', 39.1425, 34.1709), City('Kocaeli', 40.7654, 29.9408),
  City('Konya', 37.8746, 32.4932), City('Kütahya', 39.4242, 29.9833),
  City('Malatya', 38.3554, 38.3335), City('Manisa', 38.6140, 27.4296),
  City('Mardin', 37.3129, 40.7339), City('Mersin', 36.8121, 34.6415),
  City('Muğla', 37.2153, 28.3636), City('Muş', 38.7432, 41.5064),
  City('Nevşehir', 38.6244, 34.7142), City('Niğde', 37.9667, 34.6833),
  City('Ordu', 40.9862, 37.8797), City('Osmaniye', 37.0742, 36.2467),
  City('Rize', 41.0255, 40.5177), City('Sakarya', 40.7889, 30.4060),
  City('Samsun', 41.2867, 36.3300), City('Şanlıurfa', 37.1674, 38.7955),
  City('Siirt', 37.9333, 41.9500), City('Sinop', 42.0231, 35.1531),
  City('Şırnak', 37.5164, 42.4594), City('Sivas', 39.7505, 37.0150),
  City('Tekirdağ', 40.9833, 27.5167), City('Tokat', 40.3167, 36.5500),
  City('Trabzon', 41.0027, 39.7168), City('Tunceli', 39.1079, 39.5401),
  City('Uşak', 38.6823, 29.4082), City('Van', 38.5012, 43.3730),
  City('Yalova', 40.6500, 29.2667), City('Yozgat', 39.8181, 34.8147),
  City('Zonguldak', 41.4564, 31.7987),
  City('Mekke (Kabe)', 21.4225, 39.8262), City('Medine', 24.4672, 39.6111),
  City('Kudüs', 31.7683, 35.2137),
];

City nearestCity(double lat, double lng) {
  City best = turkeyCities.first;
  double bestD = double.infinity;
  for (final c in turkeyCities) {
    final d = math.pow(c.lat - lat, 2) + math.pow((c.lng - lng) * math.cos(lat * math.pi / 180), 2);
    if (d < bestD) {
      bestD = d.toDouble();
      best = c;
    }
  }
  return best;
}

/// Bir günün vakitleri ("HH:mm").
class DayTimes {
  final DateTime date;
  final String imsak, gunes, ogle, ikindi, aksam, yatsi;
  final bool fromDiyanet;

  const DayTimes({
    required this.date,
    required this.imsak,
    required this.gunes,
    required this.ogle,
    required this.ikindi,
    required this.aksam,
    required this.yatsi,
    required this.fromDiyanet,
  });

  /// daily_prayers anahtarına göre vakit saati.
  String timeFor(String key) => switch (key) {
        'fajr' => imsak,
        'dhuhr' => ogle,
        'asr' => ikindi,
        'maghrib' => aksam,
        'isha' => yatsi,
        _ => imsak,
      };

  DateTime at(String hhmm) {
    final p = hhmm.split(':');
    return DateTime(date.year, date.month, date.day, int.parse(p[0]), int.parse(p[1]));
  }

  /// Tüm vakitler (ad, saat) sırayla.
  List<(String, String)> get all => [
        ('İmsak', imsak),
        ('Güneş', gunes),
        (date.weekday == DateTime.friday ? 'Cuma' : 'Öğle', ogle),
        ('İkindi', ikindi),
        ('Akşam', aksam),
        ('Yatsı', yatsi),
      ];

  Map<String, String> toJson() => {
        'imsak': imsak, 'gunes': gunes, 'ogle': ogle,
        'ikindi': ikindi, 'aksam': aksam, 'yatsi': yatsi,
      };

  static DayTimes fromJson(DateTime date, Map<String, dynamic> j, bool diyanet) => DayTimes(
        date: date,
        imsak: j['imsak'] as String,
        gunes: j['gunes'] as String,
        ogle: j['ogle'] as String,
        ikindi: j['ikindi'] as String,
        aksam: j['aksam'] as String,
        yatsi: j['yatsi'] as String,
        fromDiyanet: diyanet,
      );
}

class NextPrayer {
  final String name;
  final String time;
  final Duration remaining;
  const NextPrayer(this.name, this.time, this.remaining);
}

class PrayerTimesService {
  static String _key(DateTime d, double lat, double lng) =>
      'pt_${DateFormat('yyyy-MM-dd').format(d)}_${lat.toStringAsFixed(2)}_${lng.toStringAsFixed(2)}';

  /// Diyanet (aladhan method=13) vakitleri; önbellek → ağ → yerel hesap.
  static Future<DayTimes> forDate(DateTime date) async {
    final day = DateTime(date.year, date.month, date.day);
    final lat = AppSettings.lat, lng = AppSettings.lng;
    final key = _key(day, lat, lng);
    final cached = AppSettings.prefs.getString(key);
    if (cached != null) {
      return DayTimes.fromJson(day, jsonDecode(cached) as Map<String, dynamic>, true);
    }
    try {
      final t = await _fetch(day, lat, lng);
      await AppSettings.prefs.setString(key, jsonEncode(t.toJson()));
      return t;
    } catch (_) {
      return calculate(day, lat, lng);
    }
  }

  /// Önümüzdeki 30 günün Diyanet vakitlerini tek seferde önbelleğe alır (bu ay + gelecek ay,
  /// aladhan aylık takvim). Böylece internet uzun süre olmasa da hatırlatmalar Diyanet saatiyle kurulur.
  /// Eksik gün yoksa ağa çıkmaz. Dönüş: önbelleğe yeni yazılan gün sayısı.
  static Future<int> prefetch30() async {
    final lat = AppSettings.lat, lng = AppSettings.lng;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final missing = [
      for (var i = 0; i < 30; i++)
        if (AppSettings.prefs.getString(_key(today.add(Duration(days: i)), lat, lng)) == null)
          today.add(Duration(days: i)),
    ];
    if (missing.isEmpty) return 0;
    final months = {for (final d in missing) (d.year, d.month)};
    var saved = 0;
    for (final (y, m) in months) {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      try {
        final req = await client.getUrl(Uri.parse(
            'https://api.aladhan.com/v1/calendar/$y/$m?latitude=$lat&longitude=$lng&method=13'));
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;
        final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
        for (final e in (body['data'] as List)) {
          final t = (e as Map)['timings'] as Map;
          final g = ((e['date'] as Map)['gregorian'] as Map)['date'] as String; // dd-MM-yyyy
          final day = DateFormat('dd-MM-yyyy').parse(g);
          if (day.isBefore(today)) continue;
          String c(String k) => (t[k] as String).trim().substring(0, 5);
          final dt = DayTimes(
            date: day,
            imsak: c('Fajr'),
            gunes: c('Sunrise'),
            ogle: c('Dhuhr'),
            ikindi: c('Asr'),
            aksam: c('Maghrib'),
            yatsi: c('Isha'),
            fromDiyanet: true,
          );
          await AppSettings.prefs.setString(_key(day, lat, lng), jsonEncode(dt.toJson()));
          saved++;
        }
      } catch (_) {
        // internet yok: bir sonraki açılışta tekrar denenir
      } finally {
        client.close();
      }
    }
    // Eski günlerin önbelleğini temizle (7 günden eski)
    final old = DateFormat('yyyy-MM-dd').format(today.subtract(const Duration(days: 7)));
    for (final k in AppSettings.prefs.getKeys().where((k) => k.startsWith('pt_')).toList()) {
      final d = k.length >= 13 ? k.substring(3, 13) : '';
      if (d.compareTo(old) < 0) await AppSettings.prefs.remove(k);
    }
    return saved;
  }

  static Future<DayTimes> _fetch(DateTime day, double lat, double lng) async {
    final ds = DateFormat('dd-MM-yyyy').format(day);
    final uri = Uri.parse(
        'https://api.aladhan.com/v1/timings/$ds?latitude=$lat&longitude=$lng&method=13');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final t = (body['data'] as Map<String, dynamic>)['timings'] as Map<String, dynamic>;
      String c(String k) => (t[k] as String).trim().substring(0, 5);
      return DayTimes(
        date: day,
        imsak: c('Fajr'),
        gunes: c('Sunrise'),
        ogle: c('Dhuhr'),
        ikindi: c('Asr'),
        aksam: c('Maghrib'),
        yatsi: c('Isha'),
        fromDiyanet: true,
      );
    } finally {
      client.close();
    }
  }

  /// Yerel yaklaşık hesap (internet yoksa) — eski PrayerCalculator.kt ile aynı.
  static DayTimes calculate(DateTime day, double lat, double lng) {
    final dayOfYear = day.difference(DateTime(day.year, 1, 1)).inDays + 1;
    const tz = 3.0;
    final b = 2 * math.pi * (dayOfYear - 81) / 365.0;
    final eot = 9.87 * math.sin(2 * b) - 7.53 * math.cos(b) - 1.5 * math.sin(b);
    final decl = _rad(23.45 * math.sin(_rad((360.0 / 365.0) * (dayOfYear - 81))));
    final latR = _rad(lat);
    final noon = 12.0 - (lng / 15.0) - (eot / 60.0) + tz;

    double ha(double alt) {
      final c = (math.sin(alt) - math.sin(latR) * math.sin(decl)) / (math.cos(latR) * math.cos(decl));
      return _deg(math.acos(c.clamp(-1.0, 1.0))) / 15.0;
    }

    final sunHa = ha(-_rad(0.833));
    final fajrHa = ha(-_rad(18.0));
    final ishaHa = ha(-_rad(17.0));
    final asrAlt = math.atan(1.0 / (1.0 + math.tan((latR - decl).abs())));
    final asrHa = ha(asrAlt);

    return DayTimes(
      date: day,
      imsak: _fmt(noon - fajrHa),
      gunes: _fmt(noon - sunHa),
      ogle: _fmt(noon + 5 / 60),
      ikindi: _fmt(noon + asrHa),
      aksam: _fmt(noon + sunHa + 7 / 60),
      yatsi: _fmt(noon + ishaHa),
      fromDiyanet: false,
    );
  }

  static NextPrayer next(DayTimes today, DayTimes tomorrow) {
    final now = DateTime.now();
    for (final (name, t) in today.all) {
      final at = today.at(t);
      if (at.isAfter(now)) return NextPrayer(name, t, at.difference(now));
    }
    final at = tomorrow.at(tomorrow.imsak);
    return NextPrayer('İmsak', tomorrow.imsak, at.difference(now));
  }

  /// Kıble yönü (kuzeyden saat yönünde derece).
  static double qiblaBearing(double lat, double lng) {
    final kLat = _rad(21.4225), kLng = _rad(39.8262);
    final uLat = _rad(lat), uLng = _rad(lng);
    final d = kLng - uLng;
    final y = math.sin(d) * math.cos(kLat);
    final x = math.cos(uLat) * math.sin(kLat) - math.sin(uLat) * math.cos(kLat) * math.cos(d);
    return (_deg(math.atan2(y, x)) + 360) % 360;
  }

  static double _rad(double d) => d * math.pi / 180;
  static double _deg(double r) => r * 180 / math.pi;

  static String _fmt(double hours) {
    var h = hours % 24.0;
    if (h < 0) h += 24.0;
    final total = (h * 60).round();
    final hh = (total ~/ 60) % 24, mm = total % 60;
    return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }
}
