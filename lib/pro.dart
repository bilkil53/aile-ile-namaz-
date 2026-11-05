import 'package:flutter/material.dart';

import 'data.dart';
import 'settings.dart';

/// Pro / Demo durumu.
/// - Yeni kullanıcı: ilk girişte 7 gün Pro deneme (sunucu ensure_pro_trial).
/// - Süre bitince Demo: bazı özellikler kilitlenir.
/// - Pro kodu girilince (redeem_pro_code) tekrar Pro.
/// - Aile Pro'su: reis (havuz sahibi) Pro alınca havuzdaki herkes Pro olur; deneme kişiye özeldir.
/// Durum hesaba bağlıdır (sunucu my_pro_status) ve telefonda önbelleğe alınır (çevrimdışı çalışır).
class Pro {
  static const _kUntil = 'pro.until'; // ms since epoch, 0 = yok
  static const _kSource = 'pro.source'; // paid | family | trial | ''
  static const _kTrial = 'pro.trialUntil';

  /// Pro'nun kaynağı: 'paid' (kendi aldı), 'family' (reisin aboneliği), 'trial' (7 gün deneme), null (demo).
  static String? source;

  /// Kişisel 7 günlük denemenin bitişi (başlangıç = bitiş − 7 gün).
  static DateTime? trialUntil;

  /// Demo ne zamandan beri: Pro/deneme süresinin bittiği an.
  static DateTime? get demoSince => isDemo ? _until : null;

  static DateTime? get trialStart => trialUntil?.subtract(const Duration(days: 7));

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

  static String fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Ayarlar ve Pro kartları için kısa durum yazısı.
  static String statusText() {
    final u = _until;
    if (isDemo) {
      final t = trialStart;
      final since = u == null ? '' : ' · ${fmt(u)} tarihinden beri';
      final trial = (t != null && trialUntil != null) ? ' (7 günlük deneme ${fmt(t)}–${fmt(trialUntil!)})' : '';
      return 'Demo sürüm$since$trial';
    }
    final until = u == null ? '' : ' · ${fmt(u)} tarihine kadar';
    return switch (source) {
      'family' => 'Pro$until · Aile Reisinin aboneliğiyle 👨‍👩‍👧',
      'trial' => 'Pro deneme · $daysLeft gün kaldı${trialUntil == null ? '' : ' (${fmt(trialUntil!)} bitiyor)'}',
      _ => 'Pro$until',
    };
  }

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
    final src = AppSettings.prefs.getString(_kSource) ?? '';
    source = src.isEmpty ? null : src;
    final t = AppSettings.prefs.getInt(_kTrial) ?? 0;
    trialUntil = t > 0 ? DateTime.fromMillisecondsSinceEpoch(t) : null;
  }

  static DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  /// Sunucudan ayrıntılı durumu oku (kaynak, deneme bitişi, etkin bitiş).
  static Future<void> refresh() async {
    if (isGuest) return;
    try {
      final r = await supa.rpc('my_pro_status').timeout(const Duration(seconds: 8));
      if (r is! Map) return;
      final oldSource = source;
      source = r['source'] as String?;
      trialUntil = _dt(r['trial_until']);
      await AppSettings.prefs.setString(_kSource, source ?? '');
      await AppSettings.prefs.setInt(_kTrial, trialUntil?.millisecondsSinceEpoch ?? 0);
      await _save(_dt(r['until']), force: oldSource != source);
    } catch (_) {}
  }

  static Future<void> _save(DateTime? u, {bool force = false}) async {
    final same = _until == u;
    _until = u;
    await AppSettings.prefs.setInt(_kUntil, u?.millisecondsSinceEpoch ?? 0);
    if (!same || force) changed.value++; // değişmediyse ekranlar/bildirimler boşuna yenilenmesin
  }

  /// Açılışta: önbellekten yükle, sonra sunucudan tazele (deneme başlat / süreyi oku).
  static Future<void> init() async {
    _load();
    if (isGuest) return;
    try {
      final r = await supa.rpc('ensure_pro_trial').timeout(const Duration(seconds: 8));
      await _save(r == null ? null : DateTime.tryParse(r as String)?.toLocal());
      await refresh();
    } catch (_) {
      // çevrimdışı: önbellekteki değer kullanılır
    }
  }

  /// Pro kodu dener. Doğruysa Pro'ya geçer; yanlışsa false.
  static Future<bool> redeem(String code) async {
    try {
      final r = await supa.rpc('redeem_pro_code', params: {'p_code': code}).timeout(const Duration(seconds: 8));
      await _save(r == null ? null : DateTime.tryParse(r as String)?.toLocal());
      await refresh();
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
      await refresh();
    } catch (_) {}
  }
}
