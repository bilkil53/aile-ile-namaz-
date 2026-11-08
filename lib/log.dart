import 'package:flutter/foundation.dart';

import 'privacy.dart';
import 'settings.dart';

/// Sessizce yutulan hataların kaydı: konsola yazılır ve son hata (konu başına) telefonda saklanır.
/// "Bildirim izinleri" ekranı bildirim hatalarını buradan gösterir.
class Log {
  static String _k(String tag) => 'log.last.$tag';

  static void warn(String tag, Object e) {
    debugPrint('[$tag] ${scrubSensitive(e.toString())}');
    try {
      final now = DateTime.now();
      final t = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final msg = scrubSensitive(e.toString());
      AppSettings.prefs.setString(_k(tag), '$t · ${msg.length > 160 ? '${msg.substring(0, 160)}…' : msg}');
    } catch (_) {}
  }

  static String? last(String tag) {
    try {
      return AppSettings.prefs.getString(_k(tag));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear(String tag) async {
    try {
      await AppSettings.prefs.remove(_k(tag));
    } catch (_) {}
  }
}
