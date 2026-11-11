import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'content/approaching_quotes.dart';
import 'content/daily_content.dart';
import 'lang.dart';
import 'prayer_times.dart';
import 'dini_gunler.dart';
import 'pro.dart';
import 'log.dart';
import 'models.dart';
import 'settings.dart';

/// Vakit hatırlatmaları ve günlük ayet/hadis bildirimi (cihaz içinde zamanlanır,
/// sunucuya hiçbir şey gönderilmez).
class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void>? _initF;

  // Kanal adları seçilen dilde (Android ayarlarında görünür)
  static AndroidNotificationDetails get _prayerChannel => AndroidNotificationDetails(
    'vakit_hatirlatma',
    t('Vakit hatırlatmaları', 'Prayer reminders'),
    channelDescription: t('Namaz vaktinden önce hatırlatma', 'Reminder before each prayer time'),
    importance: Importance.high,
    priority: Priority.high,
  );

  static AndroidNotificationDetails get _contentChannel => AndroidNotificationDetails(
    'gunluk_icerik',
    t('Günün ayeti ve hadisi', 'Verse and hadith of the day'),
    channelDescription: t('Her gün öğlen bir ayet, hadis veya dua', 'A verse, hadith or dua every day at noon'),
    importance: Importance.defaultImportance,
  );

  static AndroidNotificationDetails get _familyChannel => AndroidNotificationDetails(
    'aile_olaylari',
    t('Aile bildirimleri', 'Family notifications'),
    channelDescription: t('Aileden biri namaz kılınca veya dua gönderince', 'When a family member prays or sends a dua'),
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Anında bildirim (aile olayları).
  static Future<void> showFamily(int id, String title, String body) async {
    if (Pro.isDemo) return; // demo: bildirim yok
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
    } catch (e) {
      Log.warn('bildirim', e);
    }
  }

  /// Kişiye özel hatırlatma (ör. Cuma uyarısı) — aile bildirimlerinden ayrı kanal.
  static Future<void> showSpecial(int id, String title, String body) async {
    if (Pro.isDemo) return; // demo: Cuma uyarısı dahil hiçbir bildirim yok
    try {
      await init();
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'ozel_hatirlatma',
            t('Özel hatırlatmalar', 'Personal reminders'),
            channelDescription: t('Cuma namazı gibi kişiye özel hatırlatmalar', 'Personal reminders such as Friday prayer'),
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
            visibility: AppSettings.lockScreen ? NotificationVisibility.public : NotificationVisibility.private,
          ),
        ),
      );
    } catch (e) {
      Log.warn('bildirim', e);
    }
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
        ?.createNotificationChannel(AndroidNotificationChannel(
          'aile_olaylari',
          t('Aile bildirimleri', 'Family notifications'),
          description: t('Aileden biri namaz kılınca veya dua gönderince', 'When a family member prays or sends a dua'),
          importance: Importance.high,
        ));
  }

  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Bildirim izni açık mı?
  static Future<bool> enabled() async {
    try {
      await init();
      return await _plugin
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.areNotificationsEnabled() ??
          true;
    } catch (_) {
      return true;
    }
  }

  /// Bildirim izinleri ekranındaki "Test bildirimi gönder".
  static Future<void> showTest() async {
    try {
      await init();
      await _plugin.show(
        9999,
        t('🔔 Test bildirimi', '🔔 Test notification'),
        t('Bildirimler bu telefonda çalışıyor ✓', 'Notifications work on this phone ✓'),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _familyChannel.channelId,
            _familyChannel.channelName,
            channelDescription: _familyChannel.channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      Log.warn('bildirim', e);
    }
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

  /// Bu sınıfın kurduğu hatırlatma kimlikleri: 1–99 vakit, 100–199 günün içeriği, 300–399 mübarek gün.
  /// Yeniden kurarken yalnızca bunlar iptal edilir (başka bildirimlere dokunulmaz).
  static bool isManagedId(int id) => (id >= 1 && id <= 199) || (id >= 300 && id <= 399);

  static Future<void>? _running;

  /// Önümüzdeki 10 günün hatırlatmalarını yeniden kurar. Aynı anda iki kez çalışmaz (çağrılar sıraya girer).
  static Future<void> reschedule() async {
    final prev = _running;
    final done = () async {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      await _rescheduleNow();
    }();
    _running = done;
    try {
      await done;
    } finally {
      if (identical(_running, done)) _running = null;
    }
  }

  /// Önce yeni plan eksiksiz hazırlanır; hazırlanırken hata olursa (vakit servisi, bozuk önbellek)
  /// mevcut hatırlatmalara DOKUNULMAZ. Plan hazırsa yalnızca bu sınıfın kimlikleri iptal edilip yenileri kurulur.
  static Future<void> _rescheduleNow() async {
    final plan = <(int, String, String, DateTime, AndroidNotificationDetails)>[];
    if (Pro.isDemo) {
      // demo: vakit/günün ayeti/mübarek gün hatırlatmaları kurulmaz; eskiden kalan varsa kaldırılır
      await _apply(plan);
      return;
    }
    try {
      await init();
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      _exact = await android?.canScheduleExactNotifications() ?? false;
      // Önce 30 günlük Diyanet vaktini önbelleğe al (internet yoksa hızlıca geçer)
      try {
        await PrayerTimesService.prefetch30().timeout(const Duration(seconds: 20));
      } catch (e) {
        Log.warn('vakit', e);
      }
      final now = DateTime.now();
      final lead = AppSettings.reminderMinutes;
      var id = 1;
      // 10 gün ileri: uygulama 10 gün açılmasa da hatırlatmalar sürer (≈70 alarm; Android sınırı 500)
      for (var d = 0; d < 10; d++) {
        final day = DateTime(now.year, now.month, now.day).add(Duration(days: d));
        if (AppSettings.prayerReminders) {
          final pt = await PrayerTimesService.forDate(day);
          final friday = day.weekday == DateTime.friday;
          final list = [
            (prayerLabels['fajr']!, 'fajr', pt.imsak),
            (friday ? t('Cuma Namazı', 'Friday Prayer') : prayerLabels['dhuhr']!, friday ? 'cuma' : 'dhuhr', pt.ogle),
            (prayerLabels['asr']!, 'asr', pt.ikindi),
            (prayerLabels['maghrib']!, 'maghrib', pt.aksam),
            (prayerLabels['isha']!, 'isha', pt.yatsi),
          ];
          for (final (name, key, hhmm) in list) {
            final at = pt.at(hhmm).subtract(Duration(minutes: lead));
            if (at.isAfter(now)) {
              // Vakte özel hadis / ayet / dua (gün gün döner)
              final quotes = approachingQuotes[key] ?? _pool;
              final q = quotes[(_dayOfYear(day) + day.year) % quotes.length];
              final cuma = key == 'cuma';
              final title = cuma
                  ? t('🕌 Hayırlı Cumalar! Cuma Namazına $lead Dakika Kaldı ($hhmm)',
                      '🕌 Jumuah Mubarak! $lead Minutes to Friday Prayer ($hhmm)')
                  : t('🕌 $name Vaktine $lead Dakika Kaldı ($hhmm)', '🕌 $lead Minutes to $name ($hhmm)');
              final lead2 = cuma
                  ? t('Abdestini tazeleyip Cuma namazı ve hutbeye yetişmek için camiye hazırlanmayı unutma. 🤲',
                      "Don't forget to renew your wudu and get ready to reach the mosque for the Friday prayer and khutbah. 🤲")
                  : t('Haydi namaza 🤲', 'Come to prayer 🤲');
              plan.add((id, title, '$lead2\n\n${q.title}: ${q.text}\n— ${q.source}', at, _prayerChannel));
            }
            id++;
          }
        }
        if (AppSettings.dailyContent) {
          final at = DateTime(day.year, day.month, day.day, 12);
          if (at.isAfter(now)) {
            final q = dailyQuotes(day)[d % 2]; // ayet / hadis dönüşümlü
            plan.add((100 + d, q.title, q.text, at, _contentChannel));
          }
        }
      }
      // Mübarek günler: 1 gün kala akşam 19:00'da açıklamalı hatırlatma (önümüzdeki 60 gün)
      try {
        await DiniGunler.ensure().timeout(const Duration(seconds: 30));
      } catch (e) {
        Log.warn('mübarek günler', e); // eldeki liste ile devam
      }
      var did = 300;
      for (final e in DiniGunler.events) {
        final at = DateTime(e.date.year, e.date.month, e.date.day, 19).subtract(const Duration(days: 1));
        if (!at.isAfter(now) || at.difference(now).inDays > 60) continue;
        final g = e.gun;
        final when = g.eveBefore ? t('Yarın akşam', 'Tomorrow evening') : t('Yarın', 'Tomorrow');
        final title = g.bayram
            ? t('${g.emoji} $when ${g.name} · Bayramınız mübarek olsun!', '${g.emoji} $when: ${g.name} · Eid Mubarak!')
            : t('${g.emoji} $when ${g.name}', '${g.emoji} $when: ${g.name}');
        plan.add((did++, title, g.meaning, at, _contentChannel));
      }
    } catch (e) {
      // Plan hazırlanamadı: kurulu hatırlatmalar yerinde kalır, bir sonraki açılışta yeniden denenir
      Log.warn('hatırlatma planı', e);
      return;
    }
    await _apply(plan);
  }

  /// Planı uygular: önce yeniler kurulur (aynı kimlik eskisinin üzerine yazar), sonra planda olmayan
  /// eski hatırlatmalar iptal edilir. Böylece kurma yarıda kesilse bile telefon hatırlatmasız kalmaz.
  static Future<void> _apply(List<(int, String, String, DateTime, AndroidNotificationDetails)> plan) async {
    try {
      for (final (id, title, text, at, channel) in plan) {
        await _schedule(id, title, text, at, channel);
      }
    } catch (e) {
      // Bildirim izni yoksa vb.: eskiler yerinde kalır
      Log.warn('hatırlatma kurma', e);
      return;
    }
    try {
      final keep = {for (final p in plan) p.$1};
      final pending = await _plugin.pendingNotificationRequests();
      for (final r in pending) {
        if (isManagedId(r.id) && !keep.contains(r.id)) await _plugin.cancel(r.id);
      }
    } catch (e) {
      Log.warn('eski hatırlatma temizliği', e);
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
