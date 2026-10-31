import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

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
    storageBucket: 'aile-ile-namaz-d437f.firebasestorage.app',
  );

  /// Son hatanın ayrıntısı (Ayarlar'da dokununca gösterilir; destek için).
  static String lastErrorDetail = '';

  static String _detail(Object e) {
    if (e is PlatformException) {
      return 'code: ${e.code}\nmessage: ${e.message}\ndetails: ${e.details}\nstack: ${e.stacktrace ?? ''}';
    }
    return e.toString();
  }

  static bool _ready = false;

  /// Ayarlar'da gösterilen durum: telefonun anlık bildirime kayıtlı olup olmadığı.
  static final status = ValueNotifier<String>('Kontrol ediliyor…');
  static bool ok = false;
  static String? _token;
  static StreamSubscription<String>? _refreshSub;

  static Future<void>? _initF;

  /// Tek seferlik başlatma (aynı anda iki yerden çağrılsa da bir kez çalışır).
  static Future<void> init() => _initF ??= _init();

  static Future<void> _init() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    Object? lastError;
    // Sessizce 3 kez dene (5 sn arayla); olmazsa Ayarlar'da uyarı göster
    for (var attempt = 1; attempt <= 3 && !_ready; attempt++) {
      try {
        if (Firebase.apps.isEmpty) {
          try {
            // google-services.json ile Android tarafında hazırlanan varsayılan uygulama
            await Firebase.initializeApp();
          } catch (e) {
            if (!(e is FirebaseException && e.code == 'duplicate-app')) {
              lastErrorDetail = _detail(e);
              // Yedek: aynı ayarlarla elle başlat
              await Firebase.initializeApp(options: _options);
            }
          }
        }
        Firebase.app(); // varsayılan uygulama gerçekten var mı?
        _ready = true;
      } on FirebaseException catch (e) {
        if (e.code == 'duplicate-app') {
          _ready = true; // zaten açık: sorun yok
        } else {
          lastError = e;
        }
      } catch (e) {
        lastError = e;
        lastErrorDetail = '${lastErrorDetail.isEmpty ? '' : '$lastErrorDetail\n\n--- yedek deneme ---\n'}${_detail(e)}';
      }
      if (!_ready && attempt < 3) await Future<void>.delayed(const Duration(seconds: 5));
    }
    if (!_ready) {
      _initF = null; // sonraki açılışta / "tekrar dene"de yeniden denensin
      _set(false, 'Firebase başlatılamadı (${_short(lastError ?? 'bilinmeyen hata')})');
      return;
    }
    // Çökme raporları (Firebase Crashlytics): hata olursa geliştiriciye anonim rapor gider
    try {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (_) {}
  }

  /// Giriş yapılmışsa ve aile bildirimleri açıksa cihazı kaydeder.
  static Future<void> register() async {
    if (!ok) status.value = 'Hazırlanıyor…';
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
      String? t;
      for (var i = 0; i < 3 && t == null; i++) {
        try {
          t = await fm.getToken();
        } catch (_) {
          if (i == 2) rethrow;
          await Future<void>.delayed(const Duration(seconds: 5));
        }
      }
      if (t == null) return _set(false, 'Cihaz adresi alınamadı');
      await _save(t, strict: true);
      _refreshSub ??= fm.onTokenRefresh.listen(_save);
      _set(true, 'Hazır ✓ Uygulama kapalıyken de bildirim gelir');
    } catch (e) {
      lastErrorDetail = _detail(e);
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
