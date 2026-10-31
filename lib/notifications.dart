import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'content/daily_content.dart';
import 'prayer_times.dart';
import 'settings.dart';

/// Vakit hatırlatmaları ve günlük ayet/hadis bildirimi (cihaz içinde zamanlanır,
/// sunucuya hiçbir şey gönderilmez).
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void>? _initF;

  static const _prayerChannel = AndroidNotificationDetails(
    'vakit_hatirlatma',
    'Vakit hatırlatmaları',
    channelDescription: 'Namaz vaktinden önce hatırlatma',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _contentChannel = AndroidNotificationDetails(
    'gunluk_icerik',
    'Günün ayeti ve hadisi',
    channelDescription: 'Her gün öğlen bir ayet, hadis veya dua',
    importance: Importance.defaultImportance,
  );

  static const _familyChannel = AndroidNotificationDetails(
    'aile_olaylari',
    'Aile bildirimleri',
    channelDescription: 'Aileden biri namaz kılınca veya dua gönderince',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Anında bildirim (aile olayları).
  static Future<void> showFamily(int id, String title, String body) async {
    try {
      await init();
      await _plugin.show(1000 + (id % 100000), title, body, const NotificationDetails(android: _familyChannel));
    } catch (_) {}
  }

  static Future<void> init() => _initF ??= _init();

  static Future<void> _init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Önümüzdeki 3 günün hatırlatmalarını yeniden kurar.
  static Future<void> reschedule() async {
    try {
      await init();
      await _plugin.cancelAll();
      final now = DateTime.now();
      final lead = AppSettings.reminderMinutes;
      var id = 1;
      for (var d = 0; d < 3; d++) {
        final day = DateTime(now.year, now.month, now.day).add(Duration(days: d));
        if (AppSettings.prayerReminders) {
          final t = await PrayerTimesService.forDate(day);
          final list = [
            ('Sabah', t.imsak),
            (day.weekday == DateTime.friday ? 'Cuma' : 'Öğle', t.ogle),
            ('İkindi', t.ikindi),
            ('Akşam', t.aksam),
            ('Yatsı', t.yatsi),
          ];
          for (final (name, hhmm) in list) {
            final at = t.at(hhmm).subtract(Duration(minutes: lead));
            if (at.isAfter(now)) {
              await _schedule(id, '$name vakti yaklaşıyor', '$lead dakika sonra $name ($hhmm). Haydi namaza 🤲', at, _prayerChannel);
            }
            id++;
          }
        }
        if (AppSettings.dailyContent) {
          final at = DateTime(day.year, day.month, day.day, 12);
          if (at.isAfter(now)) {
            final q = dailyQuotes(day)[d % 2]; // ayet / hadis dönüşümlü
            await _schedule(100 + d, q.title, q.text, at, _contentChannel);
          }
        }
      }
    } catch (_) {
      // Bildirim izni yoksa vb. sessizce geç.
    }
  }

  static Future<void> _schedule(int id, String title, String body, DateTime at,
      AndroidNotificationDetails channel) {
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(at, tz.local),
      NotificationDetails(android: channel),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
