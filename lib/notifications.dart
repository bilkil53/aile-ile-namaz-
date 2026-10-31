import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'content/approaching_quotes.dart';
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
      await _plugin.show(
        1000 + (id % 100000),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _familyChannel.channelId,
            _familyChannel.channelName,
            channelDescription: _familyChannel.channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            // Kilit ekranında içerik: kullanıcının tercihine göre
            visibility: AppSettings.lockScreen ? NotificationVisibility.public : NotificationVisibility.private,
          ),
        ),
      );
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
    // FCM bildirimleri (uygulama kapalıyken) bu kanala düşer; önceden oluşturulmalı
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          'aile_olaylari',
          'Aile bildirimleri',
          description: 'Aileden biri namaz kılınca veya dua gönderince',
          importance: Importance.high,
        ));
  }

  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Vakit hatırlatmalarının dakikası dakikasına gelmesi için "Alarm ve hatırlatıcılar" izni (Android 12+).
  static Future<bool> exactAllowed() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.canScheduleExactNotifications() ??
      false;

  static Future<void> requestExact() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
  }

  static bool _exact = false;

  /// Önümüzdeki 3 günün hatırlatmalarını yeniden kurar.
  static Future<void> reschedule() async {
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      _exact = await android?.canScheduleExactNotifications() ?? false;
      await _plugin.cancelAll();
      final now = DateTime.now();
      final lead = AppSettings.reminderMinutes;
      var id = 1;
      for (var d = 0; d < 3; d++) {
        final day = DateTime(now.year, now.month, now.day).add(Duration(days: d));
        if (AppSettings.prayerReminders) {
          final t = await PrayerTimesService.forDate(day);
          final friday = day.weekday == DateTime.friday;
          final list = [
            ('Sabah', 'fajr', t.imsak),
            (friday ? 'Cuma Namazı' : 'Öğle', friday ? 'cuma' : 'dhuhr', t.ogle),
            ('İkindi', 'asr', t.ikindi),
            ('Akşam', 'maghrib', t.aksam),
            ('Yatsı', 'isha', t.yatsi),
          ];
          for (final (name, key, hhmm) in list) {
            final at = t.at(hhmm).subtract(Duration(minutes: lead));
            if (at.isAfter(now)) {
              // Eski uygulamadaki gibi vakte özel hadis / ayet / dua (gün gün döner)
              final quotes = approachingQuotes[key] ?? _pool;
              final q = quotes[(_dayOfYear(day) + day.year) % quotes.length];
              final cuma = key == 'cuma';
              final title = cuma
                  ? '🕌 Hayırlı Cumalar! Cuma Namazına $lead Dakika Kaldı ($hhmm)'
                  : '🕌 $name Vaktine $lead Dakika Kaldı ($hhmm)';
              final lead2 = cuma
                  ? 'Abdestini tazeleyip Cuma namazı ve hutbeye yetişmek için camiye hazırlanmayı unutma. 🤲'
                  : 'Haydi namaza 🤲';
              await _schedule(id, title, '$lead2\n\n${q.title}: ${q.text}\n— ${q.source}', at, _prayerChannel);
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

  static final _pool = [...hadisler, ...dualar, ...ozluSozler];
  static int _dayOfYear(DateTime d) => d.difference(DateTime(d.year, 1, 1)).inDays + 1;

  static Future<void> _schedule(int id, String title, String body, DateTime at,
      AndroidNotificationDetails channel) {
    // Uzun metin bildirimde açılınca tamamı görünsün
    final details = AndroidNotificationDetails(
      channel.channelId,
      channel.channelName,
      channelDescription: channel.channelDescription,
      importance: channel.importance,
      priority: channel.priority,
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
    );
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(at, tz.local),
      NotificationDetails(android: details),
      // Tam zamanında: izin varsa kesin alarm, yoksa Android'in esnek zamanlaması
      androidScheduleMode: _exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }
}
