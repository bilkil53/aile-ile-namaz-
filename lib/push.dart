import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'data.dart';
import 'settings.dart';

/// Uygulama kapalıyken de aile bildirimleri (Firebase Cloud Messaging).
///
/// Akış: telefon FCM'den bir cihaz adresi (token) alır → Supabase `devices` tablosuna yazılır
/// (RLS: herkes sadece kendi satırını görür). Aileden biri `pool_events`'e kayıt eklediğinde
/// veritabanı tetikleyicisi `push-family` sunucu fonksiyonunu çağırır; fonksiyon diğer üyelerin
/// cihazlarına bildirim gönderir. Uygulama açıkken bildirimi Realtime dinleyicisi gösterir.
class Push {
  // Firebase istemci ayarları (google-services.json karşılığı). Gizli değildir; APK'nın içinde de bulunur.
  // Güvenlik Firebase tarafında API kısıtlamalarıyla, veri güvenliği Supabase RLS ile sağlanır.
  static const _options = FirebaseOptions(
    apiKey: 'AIzaSyAN2lEI-gh97nI9RMp1gkRpthTBsUHn4sQ',
    appId: '1:736837751684:android:dc1c39574b3dcbd945c3d1',
    messagingSenderId: '736837751684',
    projectId: 'aile-ile-namaz-d437f',
  );

  static bool _ready = false;

  /// Ayarlar'da gösterilen durum: telefonun anlık bildirime kayıtlı olup olmadığı.
  static final status = ValueNotifier<String>('Kontrol ediliyor…');
  static bool ok = false;
  static String? _token;
  static StreamSubscription<String>? _refreshSub;

  static Future<void> init() async {
    if (_ready || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      // google-services.json (derlemede eklenir) Android tarafında varsayılan uygulamayı zaten açar.
      // Ayarlarla ikinci kez açmaya çalışmak "duplicate-app" hatası verir; önce mevcut olanı kullan.
      if (Firebase.apps.isEmpty) {
        try {
          await Firebase.initializeApp();
        } catch (_) {
          await Firebase.initializeApp(options: _options);
        }
      }
      _ready = true;
      // Çökme raporları (Firebase Crashlytics): hata olursa geliştiriciye anonim rapor gider
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      _set(false, 'Firebase başlatılamadı: ${_short(e)}');
    }
  }

  /// Giriş yapılmışsa ve aile bildirimleri açıksa cihazı kaydeder.
  static Future<void> register() async {
    await init();
    if (!_ready) return;
    if (isGuest) return _set(false, 'Giriş yapılmadı');
    if (!AppSettings.familyAlerts) {
      await unregister();
      return _set(false, 'Aile bildirimleri kapalı');
    }
    try {
      final fm = FirebaseMessaging.instance;
      await fm.setAutoInitEnabled(true);
      final t = await fm.getToken();
      if (t == null) return _set(false, 'Cihaz adresi alınamadı');
      await _save(t, strict: true);
      _refreshSub ??= fm.onTokenRefresh.listen(_save);
      _set(true, 'Hazır ✓ Uygulama kapalıyken de bildirim gelir');
    } catch (e) {
      _set(false, 'Kayıt olmadı: ${_short(e)}');
    }
  }

  static Future<void> _save(String t, {bool strict = false}) async {
    if (isGuest) return;
    _token = t;
    try {
      await supa.from('devices').upsert({
        'user_id': myId,
        'fcm_token': t,
        'platform': 'android',
        'notify_prayer': AppSettings.notifyPrayer,
        'notify_kaza': AppSettings.notifyKaza,
        'notify_dua': AppSettings.notifyDua,
        'lock_screen': AppSettings.lockScreen,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,fcm_token');
    } catch (e) {
      if (strict) rethrow;
    }
  }

  static void _set(bool good, String text) {
    ok = good;
    status.value = text;
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 90 ? '${s.substring(0, 90)}…' : s;
  }

  /// Çıkış yaparken / aile bildirimleri kapatılınca bu cihaza bildirim gitmesin.
  static Future<void> unregister() async {
    await init();
    if (!_ready || isGuest) return;
    try {
      final t = _token ?? await FirebaseMessaging.instance.getToken();
      if (t != null) await supa.from('devices').delete().eq('user_id', myId).eq('fcm_token', t);
    } catch (_) {}
  }
}
