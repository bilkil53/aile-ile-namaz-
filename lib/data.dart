import 'dart:async';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_store.dart';
import 'settings.dart';
import 'models.dart';

SupabaseClient get supa => Supabase.instance.client;

/// Giriş yapılmadıysa (misafir) 'local'.
String get myId => supa.auth.currentUser?.id ?? 'local';

bool get isGuest => supa.auth.currentUser == null;

String todayStr() => DateFormat('yyyy-MM-dd').format(DateTime.now());

/// Tüm sunucu işlemleri burada. Yetki kontrolü veritabanında (RLS + fonksiyonlar)
/// yapılır; istemci sadece çağırır.
class Repo {
  // ---- Havuzlar ----
  static Future<List<Pool>> myPools() async {
    final rows = await supa
        .from('pools')
        .select('id, name, owner_id, invite_code')
        .order('created_at');
    return rows.map<Pool>((r) => Pool.fromMap(r)).toList();
  }

  /// Geçersiz kodda false döner. Başarılıysa yöneticiye istek gitmiş olur.
  static Future<bool> requestJoin(String code, String role, String icon) async {
    final res = await supa.rpc('request_join', params: {
      'p_code': code,
      'p_role_title': role,
      'p_icon': icon,
    });
    return res != null;
  }

  static Future<void> leavePool(String poolId) {
    invalidatePools();
    return supa.rpc('leave_pool', params: {'p_pool': poolId});
  }

  // ---- Üyeler ve yönetim ----
  static Future<List<Member>> members(String poolId) async {
    final rows = await supa
        .from('pool_members')
        .select('user_id, role_title, icon, profiles(display_name)')
        .eq('pool_id', poolId)
        .order('joined_at');
    return rows.map<Member>((r) => Member.fromMap(r)).toList();
  }

  static Future<List<JoinRequest>> pendingRequests(String poolId) async {
    final rows = await supa
        .from('join_requests')
        .select('id, user_id, role_title, icon, created_at, profiles(display_name)')
        .eq('pool_id', poolId)
        .eq('status', 'pending')
        .gte('created_at', DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String())
        .order('created_at');
    return rows.map<JoinRequest>((r) => JoinRequest.fromMap(r)).toList();
  }

  /// Reis onaylarken iki tarafın rolünü birden belirler.
  static Future<void> approveWithRoles(String requestId,
      {required String memberRole, required String memberIcon, String? ownerRole, String? ownerIcon}) =>
      supa.rpc('approve_join_with_roles', params: {
        'p_request': requestId,
        'p_member_role': memberRole,
        'p_member_icon': memberIcon,
        'p_owner_role': ownerRole,
        'p_owner_icon': ownerIcon,
      });

  /// Kendi havuzum yoksa otomatik oluşturur (davet kodu hazır gelir).
  static Future<void> ensureMyPool() async {
    invalidatePools();
    await supa.rpc('ensure_my_pool');
  }

  static Future<void> cancelRequest(String requestId) =>
      supa.rpc('cancel_join_request', params: {'p_request': requestId});

  /// Gönderdiğim bekleyen istekler: (id, havuz adı, reis adı, gönderim zamanı). 5 dk geçerli.
  static Future<List<(String, String, String, DateTime)>> myOutgoingRequests() async {
    final rows = await supa.rpc('my_outgoing_requests') as List<dynamic>;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        (
          r['id'] as String,
          r['pool_name'] as String? ?? '',
          r['owner_name'] as String? ?? '',
          DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        ),
    ];
  }

  static Future<void> setMemberRole(String poolId, String userId, String role, String icon) =>
      supa.rpc('set_member_role', params: {'p_pool': poolId, 'p_user': userId, 'p_role': role, 'p_icon': icon});

  /// Reis havuzu tamamen kapatır (üyelik ve olaylar silinir).
  static Future<void> deletePool(String poolId) async {
    invalidatePools();
    await supa.from('pools').delete().eq('id', poolId);
  }

  /// Bu kullanıcı "Muaf" işaretleyebilir mi? (erkek ünvan/simgede hayır)
  static Future<bool> canExcuse() async {
    if (isGuest) return true;
    try {
      final pools = await myPools().timeout(const Duration(seconds: 6));
      if (pools.isEmpty) return true;
      final me = (await members(pools.first.id).timeout(const Duration(seconds: 6)))
          .where((m) => m.userId == myId)
          .firstOrNull;
      return me == null || canBeExcused(me.roleTitle, me.icon);
    } catch (_) {
      return true;
    }
  }

  /// Kullanıcı adı (tüm sekmelerde aynı görünür), önbellekli.
  static String? _myName;
  static Future<String> myDisplayName() async {
    if (_myName != null) return _myName!;
    if (isGuest) return 'Misafir';
    try {
      final p = await supa
          .from('profiles')
          .select('display_name')
          .eq('id', myId)
          .maybeSingle()
          .timeout(const Duration(seconds: 6));
      final n = (p?['display_name'] as String? ?? '').trim();
      _myName = n.isNotEmpty ? n : (supa.auth.currentUser?.email ?? '').split('@').first;
      await AppSettings.prefs.setString('myName', _myName!);
      return _myName!;
    } catch (_) {
      // Çevrimdışı: son bilinen ad
      return AppSettings.prefs.getString('myName') ?? '';
    }
  }

  static Future<void> reject(String requestId) =>
      supa.rpc('reject_join', params: {'p_request': requestId});

  static Future<void> removeMember(String poolId, String userId) =>
      supa.rpc('remove_member', params: {'p_pool': poolId, 'p_user': userId});

  static Future<void> transferOwnership(String poolId, String newOwnerId) =>
      supa.rpc('transfer_ownership',
          params: {'p_pool': poolId, 'p_new_owner': newOwnerId});

  static Future<String> regenerateCode(String poolId) async {
    final res =
        await supa.rpc('regenerate_invite_code', params: {'p_pool': poolId});
    return res as String;
  }

  // ---- Namaz durumları ----
  /// Kendi kaydım: misafirde telefondan; girişliyse sunucudan (olmazsa son bilinen).
  static Future<Map<String, Map<String, PrayerStatus>>> dayPrayers(
      List<String> userIds, String date) async {
    if (userIds.isEmpty) return {};
    if (isGuest) return {myId: LocalStore.day(date)};
    try {
      final rows = await supa
          .from('daily_prayers')
          .select()
          .eq('prayer_date', date)
          .inFilter('user_id', userIds)
          .timeout(const Duration(seconds: 8));
      final out = <String, Map<String, PrayerStatus>>{};
      for (final r in rows) {
        out[r['user_id'] as String] = {
          for (final k in prayerKeys) k: PrayerStatusX.parse(r[k] as String?),
        };
      }
      // Bekleyen (gönderilmemiş) kendi işaretlerimi üstüne koy
      final mine = {...?out[myId], ..._pendingFor(date)};
      if (userIds.contains(myId)) {
        out[myId] = mine;
        await LocalStore.saveDay(date, mine);
      }
      return out;
    } catch (_) {
      if (userIds.contains(myId)) return {myId: LocalStore.day(date)};
      rethrow;
    }
  }

  static Map<String, PrayerStatus> _pendingFor(String date) => {
        for (final o in LocalStore.queue())
          if (o['t'] == 'prayer' && o['date'] == date) o['key'] as String: PrayerStatusX.parse(o['status'] as String?),
      };

  /// Aile üyelerinin tarih aralığındaki kayıtları (Birlikte Secde için): date -> userId -> durumlar
  static Future<Map<String, Map<String, Map<String, PrayerStatus>>>> rangeFor(
      List<String> userIds, DateTime from, DateTime to) async {
    if (userIds.isEmpty || isGuest) return {};
    String f(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
    final rows = await supa
        .from('daily_prayers')
        .select('user_id, prayer_date, fajr, dhuhr, asr, maghrib, isha')
        .inFilter('user_id', userIds)
        .gte('prayer_date', f(from))
        .lte('prayer_date', f(to));
    final out = <String, Map<String, Map<String, PrayerStatus>>>{};
    for (final r in rows) {
      (out[r['prayer_date'] as String] ??= {})[r['user_id'] as String] = {
        for (final k in prayerKeys) k: PrayerStatusX.parse(r[k] as String?),
      };
    }
    return out;
  }

  /// Kaza özeti: userId -> [borç, ödenen]
  static Future<Map<String, List<int>>> kazaSummary(List<String> userIds) async {
    if (userIds.isEmpty) return {};
    final rows = await supa
        .from('kaza_summary')
        .select('user_id, owed, completed')
        .inFilter('user_id', userIds);
    return {
      for (final r in rows)
        r['user_id'] as String: [
          (r['owed'] as num).toInt(),
          (r['completed'] as num).toInt(),
        ],
    };
  }

  /// Üye olunan havuz kimlikleri (önbellekli; havuz değişince [invalidatePools]).
  static List<String>? _poolIds;
  static void invalidatePools() => _poolIds = null;
  static Future<List<String>> myPoolIds() async {
    if (isGuest) return [];
    return _poolIds ??= (await myPools()).map((p) => p.id).toList();
  }

  /// Bir vakti kaydeder. İnternet yoksa telefonda bekletir, bağlantı gelince gönderir.
  /// Dönüş: true = buluta gitti, false = telefonda bekliyor / misafir.
  /// Bir vakti kaydeder. Önce telefona yazılır; buluta yazma ve aile bildirimi 5 saniye sonra,
  /// son duruma göre yapılır (hızlı değiştirmelerde tek yazma, tek bildirim). İnternet yoksa kayıt
  /// telefonda bekler ve bağlantı gelince arka planda otomatik gönderilir.
  static Future<bool> setPrayer({
    required String key,
    required PrayerStatus status,
    String? date,
  }) async {
    final day = date ?? todayStr();
    await LocalStore.setPrayer(day, key, status);
    if (isGuest) {
      await LocalStore.setHasGuestData(true);
      return false;
    }
    await LocalStore.enqueue({'t': 'prayer', 'date': day, 'key': key, 'status': status.code});
    final id = '$day|$key';
    if (day == todayStr()) _pendingAnnounce.add(id);
    _writeTimers.remove(id)?.cancel();
    _writeTimers[id] = Timer(const Duration(seconds: 5), () {
      _writeTimers.remove(id);
      unawaited(syncNow());
    });
    return true;
  }

  static final Map<String, Timer> _writeTimers = {};
  static final Set<String> _pendingAnnounce = {};
  static final Map<String, String> _announced = {};
  static Timer? _retry;
  static bool _syncing = false;

  /// Bekleyen kayıtları buluta yazar, sonra aile bildirimlerini gönderir.
  /// Gönderilemeyen kalırsa 20 saniyede bir arka planda tekrar dener.
  static Future<void> syncNow() async {
    if (isGuest || _syncing) return;
    _syncing = true;
    try {
      await flushQueue();
      if (LocalStore.pendingCount > _writeTimers.length) {
        _retry ??= Timer.periodic(const Duration(seconds: 20), (_) => syncNow());
        return;
      }
      _retry?.cancel();
      _retry = null;
      for (final id in _pendingAnnounce.toList()) {
        if (_writeTimers.containsKey(id)) continue;
        _pendingAnnounce.remove(id);
        final parts = id.split('|');
        await _announce(parts[0], parts[1]);
      }
    } finally {
      _syncing = false;
    }
  }

  static void _ensureRetry() => _retry ??= Timer.periodic(const Duration(seconds: 20), (_) => syncNow());

  /// Aileye bildirim: son duruma göre bir kez (aynı durum tekrar bildirilmez).
  static Future<void> _announce(String day, String key) async {
    if (isGuest || day != todayStr()) return;
    final id = '$day|$key';
    final status = LocalStore.day(day)[key] ?? PrayerStatus.none;
    final type = switch (status) {
      PrayerStatus.prayed => 'PRAYED',
      PrayerStatus.missed => 'MISSED',
      _ => null,
    };
    if (type == null || _announced[id] == type) return;
    try {
      final pools = await myPoolIds();
      if (pools.isEmpty) return;
      await supa.from('pool_events').insert([
        for (final p in pools)
          {'pool_id': p, 'sender_id': myId, 'event_type': type, 'prayer': key.toUpperCase()},
      ]);
      _announced[id] = type;
    } catch (_) {}
  }

  static Future<int> flushQueue() async {
    if (isGuest) return 0;
    final q = LocalStore.queue();
    var sent = 0;
    var i = 0;
    while (i < q.length) {
      final o = q[i];
      // 5 saniyelik bekleme süresi dolmamış işaretler henüz gönderilmez
      if (o['t'] == 'prayer' && _writeTimers.containsKey('${o['date']}|${o['key']}')) {
        i++;
        continue;
      }
      try {
        if (o['t'] == 'prayer') {
          await supa.from('daily_prayers').upsert(
            {'user_id': myId, 'prayer_date': o['date'], o['key'] as String: o['status']},
            onConflict: 'user_id,prayer_date',
          );
        } else if (o['t'] == 'kaza') {
          await _upsertKaza(o['type'] as String, (o['o'] as num).toInt(), (o['c'] as num).toInt());
        }
        q.removeAt(i);
        sent++;
        await LocalStore.saveQueue(q);
      } catch (_) {
        break;
      }
    }
    return sent;
  }

  /// Misafirken girilen kayıtları giriş sonrası buluta taşır.
  static Future<void> migrateGuestData() async {
    if (isGuest || !LocalStore.hasGuestData) return;
    for (final e0 in LocalStore.guestDays.entries) {
      final d = e0.key;
      final m = e0.value;
      if (m.isEmpty) continue;
      await LocalStore.saveDay(d, m);
      await supa.from('daily_prayers').upsert(
        {'user_id': myId, 'prayer_date': d, for (final e in m.entries) e.key: e.value.code},
        onConflict: 'user_id,prayer_date',
      );
    }
    if (LocalStore.guestKaza.isNotEmpty) {
      // Misafirken eklenenler hesabın mevcut kaza sayılarının üzerine eklenir (silinmez).
      final guest = Map.of(LocalStore.guestKaza);
      final cloud = await myKaza();
      for (final e in guest.entries) {
        final (o0, c0) = cloud[e.key] ?? (0, 0);
        final owed = o0 + e.value.$1, done = c0 + e.value.$2;
        await LocalStore.saveKaza(e.key, owed, done);
        await _upsertKaza(e.key, owed, done);
      }
    }
    LocalStore.clearGuest();
  }

  /// Kendi namaz kayıtlarım (tarih aralığı, Karne için).
  static Future<Map<String, Map<String, PrayerStatus>>> myRange(DateTime from, DateTime to) async {
    String f(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
    if (isGuest) {
      final out = <String, Map<String, PrayerStatus>>{};
      for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
        final m = LocalStore.day(f(d));
        if (m.isNotEmpty) out[f(d)] = m;
      }
      return out;
    }
    final rows = await supa
        .from('daily_prayers')
        .select('prayer_date, fajr, dhuhr, asr, maghrib, isha')
        .eq('user_id', myId)
        .gte('prayer_date', f(from))
        .lte('prayer_date', f(to));
    return {
      for (final r in rows)
        r['prayer_date'] as String: {
          for (final k in prayerKeys) k: PrayerStatusX.parse(r[k] as String?),
        },
    };
  }

  // ---- Kaza (detay sadece sahibine görünür) ----
  static Future<Map<String, (int, int)>> myKaza() async {
    if (isGuest) return LocalStore.kaza();
    try {
      final rows = await supa
          .from('kaza_prayers')
          .select('prayer_type, owed_count, completed_count')
          .eq('user_id', myId);
      final out = {
        for (final r in rows)
          r['prayer_type'] as String: (
            (r['owed_count'] as num).toInt(),
            (r['completed_count'] as num).toInt(),
          ),
      };
      for (final o in LocalStore.queue().where((o) => o['t'] == 'kaza')) {
        out[o['type'] as String] = ((o['o'] as num).toInt(), (o['c'] as num).toInt());
      }
      return out;
    } catch (_) {
      return LocalStore.kaza();
    }
  }

  static Future<void> _upsertKaza(String type, int owed, int completed) => supa.from('kaza_prayers').upsert({
        'user_id': myId,
        'prayer_type': type,
        'owed_count': owed,
        'completed_count': completed,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,prayer_type');

  static Future<void> saveKaza(String type, int owed, int completed, {bool announce = false}) async {
    await LocalStore.saveKaza(type, owed, completed);
    if (isGuest) {
      await LocalStore.setHasGuestData(true);
      return;
    }
    try {
      await _upsertKaza(type, owed, completed);
    } catch (_) {
      await LocalStore.enqueue({'t': 'kaza', 'type': type, 'o': owed, 'c': completed});
      _ensureRetry();
      return;
    }
    if (!announce) return;
    try {
      final pools = await myPoolIds();
      if (pools.isEmpty) return;
      // Hangi vaktin kaza edildiği paylaşılmaz; sadece "kaza kıldı" olayı.
      await supa.from('pool_events').insert([
        for (final p in pools) {'pool_id': p, 'sender_id': myId, 'event_type': 'KAZA'},
      ]);
    } catch (_) {}
  }

  /// Hesabımı ve bütün verilerimi kalıcı olarak siler.
  static Future<void> deleteMyAccount() async {
    await supa.rpc('delete_my_account');
    await supa.auth.signOut();
  }

  // ---- Olaylar ----
  static Stream<List<Map<String, dynamic>>> eventsStream(String poolId) => supa
      .from('pool_events')
      .stream(primaryKey: ['id'])
      .eq('pool_id', poolId)
      .order('created_at', ascending: false)
      .limit(5); // Son 5 hareket (sunucu 1 haftalık kaydı tutar)

  static Future<void> sendDua(String poolId, String message) async {
    await supa.from('pool_events').insert({
      'pool_id': poolId,
      'sender_id': myId,
      'event_type': 'DUA',
      'message': message,
    });
  }
}
