import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'log.dart';
import 'models.dart';
import 'sync_logic.dart';
import 'settings.dart';

/// Kayıtlar:
/// - Giriş yapmadan gezinenler (misafir): kayıt yapılmaz (gezinti yalnızca bakmak içindir);
///   giriş yapınca gezintiden hiçbir şey aktarılmaz.
/// - Giriş yapanlar için son bilinen durum (çevrimdışı gösterim) telefonda.
/// - İnternet yokken yapılan işlemlerin bekleme kuyruğu telefonda.
class LocalStore {
  static String _pk(String date) => 'lp_$date';

  /// Giriş yoksa kalıcı kayıt yapılmaz.
  static bool get _mem {
    try {
      return Supabase.instance.client.auth.currentUser == null;
    } catch (_) {
      return true; // istemci hazır değil: kalıcı yazma yapma (misafir gibi davran)
    }
  }

  // ---- Misafir (gezinti) modu: yalnızca bakmak için; her açılışta Hoş Geldiniz penceresi gelir ----
  static bool _guestMode = false;
  static bool get guestMode => _guestMode;
  static final guestChanged = ValueNotifier<int>(0);
  static Future<void> setGuestMode(bool v) async {
    _guestMode = v;
    clearGuest();
    guestChanged.value++;
  }

  // Gezinti modu yalnızca bakmak içindir: kayıt yapılmaz, giriş sonrası hiçbir şey hesaba aktarılmaz.
  // Bu bellek alanları yalnızca giriş yokken okumaların boş dönmesi içindir.
  static final Map<String, Map<String, PrayerStatus>> _gDays = {};
  static final Map<String, (int, int)> _gKaza = {};

  static void clearGuest() {
    _gDays.clear();
    _gKaza.clear();
  }

  // ---- Hesap ayrımı: telefondaki kişisel veriler tek hesaba aittir ----
  static const _kOwner = 'store.owner';

  /// Bir hesaba ait telefondaki kişisel veriler mi? (Ayarlar ve vakit önbelleği cihaza aittir, silinmez.)
  static bool isUserKey(String k) =>
      k.startsWith('lp_') ||
      k.startsWith('pro.') ||
      k.startsWith('cuma.') ||
      const {'lk', 'queue', 'myName', 'familySnapshot'}.contains(k);

  /// Telefondaki kişisel verileri (bekleyen kuyruk, gün/kaza önbelleği, ad, aile görünümü) bu hesaba
  /// bağlar. Başka bir hesabın verisi varsa önce silinir: bir hesabın bekleyen kaydı başka hesaba
  /// yazılamaz, verisi başka hesapta görünmez. Dönüş: önceki hesabın verisi silindi mi.
  /// (Eski sürümden gelen sahipsiz veri bu hesabındır sayılır: güncellemede bekleyen kayıt kaybolmaz.)
  static bool bindUser(String uid) {
    final p = AppSettings.prefs;
    final owner = p.getString(_kOwner);
    if (owner == uid) return false;
    if (owner != null) {
      // Önceki hesabın gönderilmemiş kayıtları silinmez: o hesap adına saklanır (bu hesap göremez,
      // onun adına gönderemez); önceki hesap bu telefonda tekrar girince geri yüklenir.
      parkPending(owner);
      wipeUserData();
    }
    unawaited(p.setString(_kOwner, uid));
    final back = restoreParked(uid);
    if (back > 0) Log.warn('hesap', 'saklanan $back gönderilmemiş kayıt geri yüklendi');
    return owner != null;
  }

  // ---- Saklanan (park edilmiş) gönderilmemiş kayıtlar: hesap başına, en fazla 30 gün ----
  static const _kParked = 'parked.v1';
  static const parkDays = 30;

  static Map<String, dynamic> _parked() {
    try {
      final raw = AppSettings.prefs.getString(_kParked);
      return raw == null ? {} : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  static void _saveParked(Map<String, dynamic> m) {
    final p = AppSettings.prefs;
    unawaited(m.isEmpty ? p.remove(_kParked) : p.setString(_kParked, jsonEncode(m)));
  }

  /// Bu hesabın gönderilmemiş kayıtlarını telefonda ayrı saklar (çıkışta / hesap değişiminde).
  static void parkPending(String uid, {DateTime? now}) {
    final q = queue();
    if (q.isEmpty || uid.isEmpty || uid == 'local') return;
    final m = _parked();
    final old = (m[uid] as Map?)?['queue'] as List? ?? const [];
    // Aynı vakit/kaza için en yeni kayıt kalır
    final merged = <Map<String, dynamic>>[
      for (final o in old.cast<Map>()) Map<String, dynamic>.from(o),
    ];
    for (final o in q) {
      merged.removeWhere((x) => _sameTarget(x, o));
      merged.add(o);
    }
    m[uid] = {'at': (now ?? DateTime.now()).toUtc().toIso8601String(), 'queue': merged};
    _saveParked(m);
  }

  static bool _sameTarget(Map<String, dynamic> a, Map<String, dynamic> b) =>
      a['t'] == b['t'] &&
      ((a['t'] == 'prayer' && a['date'] == b['date'] && a['key'] == b['key']) ||
          (a['t'] == 'kaza' && a['type'] == b['type']));

  /// Bu hesap için saklanan kayıtları kuyruğa geri koyar (30 günden eskiler atılır). Dönüş: kaç kayıt.
  static int restoreParked(String uid, {DateTime? now}) {
    final m = _parked();
    final t = now ?? DateTime.now();
    m.removeWhere((_, v) {
      final at = DateTime.tryParse(((v as Map?)?['at'] as String?) ?? '');
      return at == null || t.difference(at).inDays >= parkDays;
    });
    final entry = m.remove(uid) as Map?;
    _saveParked(m);
    final items = (entry?['queue'] as List?)?.cast<Map>() ?? const [];
    if (items.isEmpty) return 0;
    final q = queue();
    for (final o in items) {
      final op = Map<String, dynamic>.from(o)..remove('a');
      if (q.any((x) => _sameTarget(x, op))) continue; // telefondaki daha yeni kayıt kalır
      q.add(op);
    }
    unawaited(saveQueue(q));
    return items.length;
  }

  /// Hesap silinince o hesabın saklanan kayıtları da silinir.
  static void dropParked(String uid) {
    final m = _parked();
    if (m.remove(uid) != null) _saveParked(m);
  }

  static int parkedCount(String uid) => (((_parked()[uid] as Map?)?['queue'] as List?) ?? const []).length;

  /// Hesaba ait telefondaki bütün kişisel verileri siler (çıkışta, hesap silmede, hesap değişince).
  /// Bellekteki önbellek hemen güncellenir; diske yazma arka planda tamamlanır.
  static void wipeUserData() {
    final p = AppSettings.prefs;
    for (final k in p.getKeys().where(isUserKey).toList()) {
      unawaited(p.remove(k));
    }
    unawaited(p.remove(_kOwner));
    clearGuest();
    // Ekran çizimi sırasında çağrılabilir (giriş kapısı): bildirim çizim bitince yapılır
    scheduleMicrotask(() => queueChanged.value++);
  }

  /// Eski sürümlerin kalıcı misafir bayraklarını ve test dönemi önbelleğini bir kez temizle.
  /// (Test sürümlerinde telefona yazılmış işaretler ve bekleyen kuyruk tekrar buluta gitmesin.)
  static Future<void> cleanupLegacy() async {
    final p = AppSettings.prefs;
    await p.remove('guestMode');
    await p.remove('guestData');
    await p.remove('guestMergeId'); // önceki sürüm kimliği telefona yazıyordu
    if ((p.getInt('dataReset') ?? 0) < 1) {
      for (final k in p.getKeys().where((k) => k.startsWith('lp_')).toList()) {
        await p.remove(k);
      }
      await p.remove('lk');
      await p.remove('queue');
      await p.setInt('dataReset', 1);
    }
  }

  // ---- Günlük namaz ----
  static Map<String, PrayerStatus> day(String date) {
    if (_mem) return Map.of(_gDays[date] ?? const {});
    final raw = AppSettings.prefs.getString(_pk(date));
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {for (final e in m.entries) e.key: PrayerStatusX.parse(e.value as String?)};
  }

  static Future<void> saveDay(String date, Map<String, PrayerStatus> m) async {
    if (_mem) {
      _gDays[date] = Map.of(m);
      return;
    }
    await AppSettings.prefs.setString(_pk(date), jsonEncode({for (final e in m.entries) e.key: e.value.code}));
  }

  static Future<void> setPrayer(String date, String key, PrayerStatus s) async {
    final m = day(date);
    m[key] = s;
    await saveDay(date, m);
  }

  // ---- Kaza ----
  static Map<String, (int, int)> kaza() {
    if (_mem) return Map.of(_gKaza);
    final raw = AppSettings.prefs.getString('lk');
    if (raw == null) return {};
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final e in m.entries)
        e.key: (((e.value as List)[0] as num).toInt(), ((e.value as List)[1] as num).toInt()),
    };
  }

  static Future<void> saveKaza(String type, int owed, int done) async {
    if (_mem) {
      _gKaza[type] = (owed, done);
      return;
    }
    final m = kaza();
    m[type] = (owed, done);
    await AppSettings.prefs.setString('lk', jsonEncode({for (final e in m.entries) e.key: [e.value.$1, e.value.$2]}));
  }

  // ---- Bekleme kuyruğu (çevrimdışı) ----
  static List<Map<String, dynamic>> queue() {
    final raw = AppSettings.prefs.getString('queue');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  /// Bekleyen kayıtlar değişince artar (ekrandaki ⏳ / ☁️✓ simgesi sessizce güncellensin).
  static final queueChanged = ValueNotifier<int>(0);

  static Future<void> saveQueue(List<Map<String, dynamic>> q) async {
    final w = AppSettings.prefs.setString('queue', jsonEncode(q));
    queueChanged.value++;
    await w;
  }

  /// Bu vaktin işareti henüz buluta gönderilmedi mi (telefonda bekliyor mu)?
  static bool isPrayerPending(String date, String key) =>
      queue().any((o) => o['t'] == 'prayer' && o['date'] == date && o['key'] == key);

  static Future<void> enqueue(Map<String, dynamic> op) async {
    final q = queue();
    // Aynı vakit/kaza için eski kaydı en yenisiyle değiştir
    q.removeWhere((o) =>
        o['t'] == op['t'] &&
        ((op['t'] == 'prayer' && o['date'] == op['date'] && o['key'] == op['key']) ||
            (op['t'] == 'kaza' && o['type'] == op['type'])));
    q.add(op);
    await saveQueue(q);
  }

  static int get pendingCount => queue().length;

  /// Kuyruğu telefondan yeniden okuyup yalnızca bu işlemi siler. (Elde tutulan eski bir kopyayı
  /// geri yazmak, gönderim sürerken eklenen yeni işaretleri silerdi.)
  static Future<void> removeOp(Map<String, dynamic> op) async {
    final q = queue();
    final i = q.indexWhere((o) => sameQueueOp(o, op));
    if (i < 0) return;
    q.removeAt(i);
    await saveQueue(q);
  }

  /// Kuyruktaki bu işlemin bir alanını günceller (yeniden okuyarak). Dönüş: işlem hâlâ kuyrukta mı.
  static Future<bool> updateOp(Map<String, dynamic> op, String field, Object value) async {
    final q = queue();
    final i = q.indexWhere((o) => sameQueueOp(o, op));
    if (i < 0) return false;
    q[i][field] = value;
    await saveQueue(q);
    return true;
  }
}
