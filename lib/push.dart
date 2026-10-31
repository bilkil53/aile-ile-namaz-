import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
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
  static String? _token;
  static StreamSubscription<String>? _refreshSub;

  static Future<void> init() async {
    if (_ready || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Firebase.initializeApp(options: _options);
      _ready = true;
    } catch (_) {}
  }

  /// Giriş yapılmışsa ve aile bildirimleri açıksa cihazı kaydeder.
  static Future<void> register() async {
    await init();
    if (!_ready || isGuest) return;
    if (!AppSettings.familyAlerts) return unregister();
    try {
      final fm = FirebaseMessaging.instance;
      await fm.setAutoInitEnabled(true);
      final t = await fm.getToken();
      if (t != null) await _save(t);
      _refreshSub ??= fm.onTokenRefresh.listen(_save);
    } catch (_) {}
  }

  static Future<void> _save(String t) async {
    if (isGuest) return;
    _token = t;
    try {
      await supa.from('devices').upsert({
        'user_id': myId,
        'fcm_token': t,
        'platform': 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,fcm_token');
    } catch (_) {}
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
