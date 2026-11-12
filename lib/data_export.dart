import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'data.dart';

/// "Verilerimi indir": kullanıcının sunucudaki kendi kayıtlarını tek bir JSON dosyasında toplar
/// (KVKK md. 11 — kişisel verilere erişim hakkı). Yalnızca kullanıcının kendi satırları okunur;
/// başka aile üyelerinin kaydı ve bildirim adresi (FCM anahtarı) dosyaya girmez.
class DataExport {
  static const _pageSize = 1000;
  static const _timeout = Duration(seconds: 15);

  /// Dosyaya girecek tablolar: (başlık, tablo, sütunlar, kullanıcı sütunu, sıralama sütunu).
  /// Sıralama sütunu kullanıcı içinde benzersizdir (sayfalar arasında satır atlanmaz / tekrarlanmaz).
  static const tables = <(String, String, String, String, String)>[
    ('profil', 'profiles', 'id, display_name, icon, created_at, kvkk_consent_at, acik_riza_at, acik_riza_version', 'id', 'id'),
    ('namaz_kayitlari', 'daily_prayers', 'prayer_date, fajr, dhuhr, asr, maghrib, isha', 'user_id', 'prayer_date'),
    ('kaza_sayilari', 'kaza_prayers', 'prayer_type, owed_count, completed_count, updated_at', 'user_id', 'prayer_type'),
    ('aile_uyelikleri', 'pool_members', 'pool_id, role_title, icon, gender, joined_at', 'user_id', 'pool_id'),
    ('katilim_istekleri', 'join_requests', 'id, pool_id, role_title, icon, status, created_at, decided_at', 'user_id', 'id'),
    ('gonderdigim_bildirim_ve_dualar', 'pool_events', 'id, pool_id, event_type, prayer, message, target_id, created_at', 'sender_id', 'id'),
    ('cihazlar', 'devices', 'platform, lang, notify_prayer, notify_kaza, notify_dua, lock_screen, updated_at', 'user_id', 'fcm_token'),
  ];

  /// Dosya içeriği (saf işlev: sınanabilir). [missing]: okunamayan bölümlerin başlıkları.
  static Map<String, dynamic> build({
    required String uid,
    required String? email,
    required DateTime at,
    required String appVersion,
    required Map<String, List<Map<String, dynamic>>> data,
    required List<String> missing,
  }) =>
      {
        'uygulama': 'Aile İle Namaz',
        'surum': appVersion,
        'olusturma_zamani': at.toUtc().toIso8601String(),
        'kullanici_kimligi': uid,
        'e_posta': email ?? '',
        'aciklama': 'Bu dosya, hesabınıza ait sunucuda tutulan kayıtların kopyasıdır. '
            'Başka aile üyelerinin kayıtları yer almaz.',
        'eksik_bolumler': missing,
        for (final t in tables) t.$1: data[t.$1] ?? const <Map<String, dynamic>>[],
      };

  static String fileName(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '$_prefix${at.year}-${two(at.month)}-${two(at.day)}.json';
  }

  static Future<List<Map<String, dynamic>>> _fetchAll(String table, String cols, String userCol, String orderCol, String uid) async {
    final out = <Map<String, dynamic>>[];
    for (var from = 0;; from += _pageSize) {
      final rows = await supa
          .from(table)
          .select(cols)
          .eq(userCol, uid)
          .order(orderCol, ascending: true)
          .range(from, from + _pageSize - 1)
          .timeout(_timeout);
      out.addAll(rows.map((r) => Map<String, dynamic>.from(r)));
      if (rows.length < _pageSize) return out;
    }
  }

  static const _prefix = 'aile-ile-namaz-verilerim-';

  /// Telefondaki eski dışa aktarma dosyalarını siler (yeni dosyadan önce ve çıkışta: başka hesap
  /// açılınca önceki hesabın dosyası telefonda kalmasın). Hata yutulur.
  static Future<void> cleanup() async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final e in dir.list()) {
        final name = e.uri.pathSegments.last;
        if (e is File && name.startsWith(_prefix) && name.endsWith('.json')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Kayıtları toplar ve geçici klasöre yazar. Dönen: (dosya, okunamayan bölümler).
  /// Hiçbir bölüm okunamazsa (internet yok / sunucu hatası) dosya üretilmez, hata fırlatılır:
  /// boş bir dosya "verilerim bu kadar" diye yanıltmasın.
  static Future<(File, List<String>)> create({required String appVersion}) async {
    final user = supa.auth.currentUser;
    if (user == null) throw StateError('oturum yok');
    final data = <String, List<Map<String, dynamic>>>{};
    final missing = <String>[];
    for (final t in tables) {
      try {
        data[t.$1] = await _fetchAll(t.$2, t.$3, t.$4, t.$5, user.id);
      } catch (_) {
        missing.add(t.$1);
      }
    }
    if (missing.length == tables.length) throw StateError('hiçbir bölüm okunamadı');
    final at = DateTime.now();
    final json = const JsonEncoder.withIndent('  ').convert(
        build(uid: user.id, email: user.email, at: at, appVersion: appVersion, data: data, missing: missing));
    await cleanup();
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${fileName(at)}');
    await f.writeAsString(json, flush: true);
    return (f, missing);
  }
}
