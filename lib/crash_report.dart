import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Basit hata raporu: beklenmedik hatalar Supabase `crash_reports` tablosuna anonim gider.
/// İçerik: sürüm, Android sürümü, o anki RAM kullanımı (MB), hata metni ve kod satırları.
/// Kişisel veri (ad, e-posta, namaz kaydı) gönderilmez. Tabloyu uygulama okuyamaz.
class CrashReport {
  static String _version = '';
  static int _build = 0;
  static int _sentThisRun = 0;
  static final Set<String> _seen = {};

  static Future<void> install() async {
    try {
      final i = await PackageInfo.fromPlatform();
      _version = i.version;
      _build = (int.tryParse(i.buildNumber) ?? 0) % 1000;
    } catch (_) {}
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      prev?.call(details);
      unawaited(send(details.exception, details.stack, fatal: false));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(send(error, stack, fatal: true));
      return true;
    };
  }

  static Future<void> send(Object error, StackTrace? stack, {bool fatal = false}) async {
    try {
      final text = error.toString();
      final key = text.length > 120 ? text.substring(0, 120) : text;
      // Aynı hatayı tekrar tekrar gönderme; bir açılışta en fazla 5 rapor
      if (!_seen.add(key) || _sentThisRun >= 5) return;
      _sentThisRun++;
      var st = stack?.toString() ?? '';
      if (st.length > 7500) st = st.substring(0, 7500);
      await Supabase.instance.client.from('crash_reports').insert({
        'app_version': _version,
        'build': _build,
        'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.substring(
            0, '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.length.clamp(0, 190)),
        'ram_mb': (ProcessInfo.currentRss / (1024 * 1024)).round(),
        'fatal': fatal,
        'error': text.length > 1900 ? text.substring(0, 1900) : text,
        'stack': st,
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // Rapor gönderilemezse (internet yok vb.) sessizce geç
    }
  }
}
