import 'package:flutter/material.dart';

import 'data.dart';
import 'settings.dart';

/// Pro / Demo durumu.
/// - Yeni kullanıcı: ilk girişte 7 gün Pro deneme (sunucu ensure_pro_trial).
/// - Süre bitince Demo: bazı özellikler kilitlenir.
/// - Pro kodu girilince (redeem_pro_code) tekrar Pro.
/// Durum hesaba bağlıdır (profiles.pro_until) ve telefonda önbelleğe alınır (çevrimdışı çalışır).
class Pro {
  static const _kUntil = 'pro.until'; // ms since epoch, 0 = yok

  /// UI bu değişince yenilenir.
  static final changed = ValueNotifier<int>(0);

  static DateTime? _until;

  static DateTime? get until => _until;

  /// Pro aktif mi? Misafirde (giriş yok) her şey açık sayılır — kısıt yalnızca girişli demo kullanıcıya.
  static bool get active {
    if (isGuest) return true;
    final u = _until;
    return u != null && u.isAfter(DateTime.now());
  }

  static bool get isDemo => !active;

  /// Kalan gün (0 veya negatifse demo). Deneme/pro arası ayrımı için.
  static int get daysLeft {
    final u = _until;
    if (u == null) return 0;
    final d = u.difference(DateTime.now()).inHours / 24;
    return d.ceil();
  }

  static void _load() {
    final ms = AppSettings.prefs.getInt(_kUntil) ?? 0;
    _until = ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  static Future<void> _save(DateTime? u) async {
    _until = u;
    await AppSettings.prefs.setInt(_kUntil, u?.millisecondsSinceEpoch ?? 0);
    changed.value++;
  }

  /// Açılışta: önbellekten yükle, sonra sunucudan tazele (deneme başlat / süreyi oku).
  static Future<void> init() async {
    _load();
    if (isGuest) return;
    try {
      final r = await supa.rpc('ensure_pro_trial').timeout(const Duration(seconds: 8));
      await _save(r == null ? null : DateTime.tryParse(r as String)?.toLocal());
    } catch (_) {
      // çevrimdışı: önbellekteki değer kullanılır
    }
  }

  /// Pro kodu dener. Doğruysa Pro'ya geçer; yanlışsa false.
  static Future<bool> redeem(String code) async {
    try {
      final r = await supa.rpc('redeem_pro_code', params: {'p_code': code}).timeout(const Duration(seconds: 8));
      await _save(r == null ? null : DateTime.tryParse(r as String)?.toLocal());
      return active;
    } catch (_) {
      return false;
    }
  }

  /// TEST: demo süresini hemen bitirir.
  static Future<void> expireTest() async {
    try {
      final r = await supa.rpc('expire_pro_test').timeout(const Duration(seconds: 8));
      await _save(r == null ? null : DateTime.tryParse(r as String)?.toLocal());
    } catch (_) {}
  }
}
