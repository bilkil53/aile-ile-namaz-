import 'package:flutter/material.dart';

import 'data.dart';
import 'lang.dart';
import 'models.dart';
import 'settings.dart';

/// Pro / Demo durumu.
/// - Yeni kullanıcı: ilk girişte 7 gün Pro deneme (sunucu ensure_pro_trial).
/// - Süre bitince Demo: bazı özellikler kilitlenir.
/// - Test listesindeki hesap "Pro'ya geç"e basınca (redeem_pro_code, kod gerekmez) tekrar Pro.
/// - Aile Pro'su: reis (havuz sahibi) Pro alınca havuzdaki herkes Pro olur; deneme kişiye özeldir.
/// Durum hesaba bağlıdır (sunucu my_pro_status) ve telefonda önbelleğe alınır (çevrimdışı çalışır).
/// Namaz Demo (test kanalı) mı: test paneli ve 🧪 etiketleri yalnızca burada.
const kTestChannel = String.fromEnvironment('CHANNEL') == 'demo';

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

  /// Denemenin başladığı an (sunucuda ayrıca tutulur; TEST düğmesi bozmaz).
  static DateTime? trialStart;
  static const _kTrialStart = 'pro.trialStart';

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

  /// Pro'yu yalnızca Aile Reisi (havuz sahibi) alabilir. Havuzda tek olan kendi havuzunun reisidir.
  static Future<bool> isReis() async {
    if (isGuest) return true;
    try {
      final pools = await Repo.myPools().timeout(const Duration(seconds: 6));
      return pools.isEmpty || pools.first.ownerId == myId;
    } catch (_) {
      return true; // bağlantı yoksa sunucu zaten kontrol eder
    }
  }

  /// Bu hesap Pro test listesinde mi? (Sunucu her işlemde ayrıca denetler; burası yalnızca
  /// test panelini ve "Pro'ya geç" düğmesini göstermek için.) Bağlantı yoksa false.
  static Future<bool> isTester() async {
    if (isGuest) return false;
    try {
      final r = await supa.rpc('am_i_pro_tester').timeout(const Duration(seconds: 6));
      return r == true;
    } catch (_) {
      return false;
    }
  }

  /// Reis olmayan üye: Aile Reisine "Pro istiyorum" iletir.
  /// Dönüş: null = iletildi, aksi halde kullanıcıya gösterilecek hata.
  static Future<String?> requestFromReis() async {
    try {
      await supa.rpc('request_pro_from_reis').timeout(const Duration(seconds: 8));
      return null;
    } catch (e) {
      final s = e.toString();
      if (s.contains('already_requested')) {
        return t('Bugün zaten ilettin. Aile Reisin bildirimi gördü 🌙', 'You already sent it today. Your head of family saw the notification 🌙');
      }
      if (s.contains('is_reis')) return t('Aile Reisi sensin; Pro\'yu sen alabilirsin.', 'You are the head of family; you can get Pro yourself.');
      return t('İletilemedi. İnternet bağlantını kontrol et.', 'Could not send. Check your internet connection.');
    }
  }

  /// Reis: isteği reddeder (kart kaybolur, isteyene bilgi gider).
  static Future<void> declineRequest(String memberId) async {
    try {
      await supa.rpc('decline_pro_request', params: {'p_member': memberId}).timeout(const Duration(seconds: 8));
      requests.value = Map.of(requests.value)..remove(memberId);
    } catch (_) {}
  }

  /// İsteyen: reis son isteğimi reddettiyse zamanı (yoksa null).
  static Future<DateTime?> myDeclinedAt() async {
    if (isGuest) return null;
    try {
      final rows = await supa
          .from('pool_events')
          .select('sender_id, event_type, created_at')
          .inFilter('event_type', ['PRO_REQUEST', 'PRO_DECLINED'])
          .or('sender_id.eq.$myId,target_id.eq.$myId')
          .gte('created_at', DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .timeout(const Duration(seconds: 8));
      if (rows.isEmpty || rows.first['event_type'] != 'PRO_DECLINED') return null;
      return DateTime.parse(rows.first['created_at'] as String).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// Reise gelen Pro istekleri (son 7 gün): gönderen kimliği → en son istek zamanı.
  static final requests = ValueNotifier<Map<String, DateTime>>({});

  static Future<void> loadRequests() async {
    if (isGuest) return;
    try {
      // Reddettiklerim: o kişiden sonraki istek gelene kadar kart görünmez
      final declined = <String, DateTime>{};
      final drows = await supa
          .from('pool_events')
          .select('target_id, created_at')
          .eq('event_type', 'PRO_DECLINED')
          .eq('sender_id', myId)
          .gte('created_at', DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String())
          .timeout(const Duration(seconds: 8));
      for (final r in drows) {
        final id = r['target_id'] as String?;
        final at = DateTime.parse(r['created_at'] as String);
        if (id != null && (declined[id] == null || at.isAfter(declined[id]!))) declined[id] = at;
      }
      final rows = await supa
          .from('pool_events')
          .select('sender_id, created_at')
          .eq('event_type', 'PRO_REQUEST')
          .eq('target_id', myId)
          .gte('created_at', DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 8));
      final m = <String, DateTime>{};
      for (final r in rows) {
        final id = r['sender_id'] as String;
        final at = DateTime.parse(r['created_at'] as String);
        if (declined[id] != null && !at.isAfter(declined[id]!)) continue;
        m.putIfAbsent(id, () => at.toLocal());
      }
      if (m.isNotEmpty) {
        try {
          final pools = await Repo.myPools();
          if (pools.isNotEmpty) {
            final ms = await Repo.members(pools.first.id);
            final me = ms.where((x) => x.userId == myId).firstOrNull;
            final reis = ms.where((x) => x.userId == pools.first.ownerId).firstOrNull;
            requestNames = {
              for (final x in ms)
                x.userId: withFirstName(
                    me == null ? x.labelFor(viewerIsReis: true) : kinLabel(viewer: me, target: x, reis: reis),
                    x.firstName),
            };
          }
        } catch (_) {}
      }
      requests.value = m;
    } catch (_) {}
  }

  static String fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Ayarlar ve Pro kartları için durum yazısı (iki satır, net tarihler).
  static String statusText() {
    final u = _until;
    final ts = trialStart, te = trialUntil;
    final now = DateTime.now();
    if (isDemo) {
      final lines = <String>[];
      if (ts != null && te != null) {
        lines.add(t('🕒 7 günlük deneme: ${fmt(ts)} – ${fmt(te)} (bitti)', '🕒 7-day trial: ${fmt(ts)} – ${fmt(te)} (ended)'));
      }
      final since = u ?? te;
      if (since != null) {
        // Takvim günü farkı (saat değil): dün gece başladıysa "dün başladı"
        final d = DateTime(now.year, now.month, now.day)
            .difference(DateTime(since.year, since.month, since.day))
            .inDays;
        lines.add(t('🔒 Ücretsiz sürümdesin · ${d <= 0 ? 'bugün başladı' : d == 1 ? 'dün başladı' : '$d gündür'}',
            '🔒 You are on the free version · ${d <= 0 ? 'since today' : d == 1 ? 'since yesterday' : 'for $d days'}'));
      } else {
        lines.add(t('🔒 Ücretsiz sürümdesin', '🔒 You are on the free version'));
      }
      return lines.join('\n');
    }
    return switch (source) {
      'trial' => t(
          '🕒 7 günlük deneme${ts != null && te != null ? ': ${fmt(ts)} – ${fmt(te)}' : ''} · $daysLeft gün kaldı'
              '\n8. gün Ücretsiz sürüme geçer: Aile Havuzu ve Kaza pasif olur, bildirimler kapanır.',
          '🕒 7-day trial${ts != null && te != null ? ': ${fmt(ts)} – ${fmt(te)}' : ''} · $daysLeft days left'
              '\nOn day 8 it switches to the free version: Family Circle and Kaza become inactive, notifications turn off.'),
      'family' => t('⭐ Pro${u == null ? '' : ' · ${fmt(u)} tarihine kadar'}\n👨‍👩‍👧 Aile Reisinin aboneliğiyle',
          '⭐ Pro${u == null ? '' : ' · until ${fmt(u)}'}\n👨‍👩‍👧 Through the head of family\'s subscription'),
      _ => t('⭐ Pro${kTestChannel ? ' (test)' : ''}${u == null ? '' : ' · ${fmt(u)} tarihine kadar'}',
          '⭐ Pro${kTestChannel ? ' (test)' : ''}${u == null ? '' : ' · until ${fmt(u)}'}'),
    };
  }

  /// Üst başlıktaki kısa test etiketi: hangi durumdayım?
  static String testLabel() {
    if (isDemo) return '🧪 Ücretsiz';
    return switch (source) {
      'trial' => '🧪 Deneme · $daysLeft gün',
      'family' => '🧪 Pro (aile)',
      _ => '🧪 Pro (test)',
    };
  }

  /// TEST: denemeyi baştan başlat (7 gün, Pro kaldırılır).
  static Future<void> testRestartTrial() async {
    try {
      await supa.rpc('test_restart_trial').timeout(const Duration(seconds: 8));
    } catch (_) {}
    await refresh();
  }

  /// Pro isteği gönderenlerin adları (ör. "Kızın Ayşe").
  static Map<String, String> requestNames = {};

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
    final tr = AppSettings.prefs.getInt(_kTrial) ?? 0;
    trialUntil = tr > 0 ? DateTime.fromMillisecondsSinceEpoch(tr) : null;
    final ts = AppSettings.prefs.getInt(_kTrialStart) ?? 0;
    trialStart = ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
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
      trialStart = _dt(r['trial_started']);
      await AppSettings.prefs.setInt(_kTrialStart, trialStart?.millisecondsSinceEpoch ?? 0);
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

  static String? lastError;

  /// Pro'ya geçer (test aşaması: yalnızca test listesindeki hesaplar, kod gerekmez; gerçek satışta
  /// Google Play ödemesine geçilecek). Başarılıysa true.
  static Future<bool> redeem([String code = '']) async {
    try {
      final r = await supa.rpc('redeem_pro_code', params: {'p_code': code}).timeout(const Duration(seconds: 8));
      await _save(r == null ? null : DateTime.tryParse(r as String)?.toLocal());
      await refresh();
      lastError = null;
      return active;
    } catch (e) {
      final s = e.toString();
      lastError = s.contains('only_reis')
          ? t('Pro\'yu yalnızca Aile Reisi alabilir.', 'Only the head of family can get Pro.')
          : s.contains('not_tester')
              ? t('Bu test sürümünde Pro yalnızca test hesaplarına açık.', 'In this test version Pro is open to test accounts only.')
              : null;
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
