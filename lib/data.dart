import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

SupabaseClient get supa => Supabase.instance.client;

String get myId => supa.auth.currentUser!.id;

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

  static Future<void> createPool(String name, String role, String icon) async {
    invalidatePools();
    await supa.rpc('create_pool', params: {
      'p_name': name,
      'p_role_title': role,
      'p_icon': icon,
    });
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
        .select('id, user_id, role_title, icon, profiles(display_name)')
        .eq('pool_id', poolId)
        .eq('status', 'pending')
        .order('created_at');
    return rows.map<JoinRequest>((r) => JoinRequest.fromMap(r)).toList();
  }

  static Future<void> approve(String requestId) =>
      supa.rpc('approve_join', params: {'p_request': requestId});

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

  /// Gönderdiğim bekleyen istekler: (id, havuz adı, reis adı)
  static Future<List<(String, String, String)>> myOutgoingRequests() async {
    final rows = await supa.rpc('my_outgoing_requests') as List<dynamic>;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        (r['id'] as String, r['pool_name'] as String? ?? '', r['owner_name'] as String? ?? ''),
    ];
  }

  static Future<void> setMemberRole(String poolId, String userId, String role, String icon) =>
      supa.rpc('set_member_role', params: {'p_pool': poolId, 'p_user': userId, 'p_role': role, 'p_icon': icon});

  /// Reis havuzu tamamen kapatır (üyelik ve olaylar silinir).
  static Future<void> deletePool(String poolId) async {
    invalidatePools();
    await supa.from('pools').delete().eq('id', poolId);
  }

  /// Kullanıcı adı (tüm sekmelerde aynı görünür), önbellekli.
  static String? _myName;
  static Future<String> myDisplayName() async {
    if (_myName != null) return _myName!;
    final p = await supa.from('profiles').select('display_name').eq('id', myId).maybeSingle();
    final n = (p?['display_name'] as String? ?? '').trim();
    _myName = n.isNotEmpty ? n : (supa.auth.currentUser?.email ?? '').split('@').first;
    return _myName!;
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
  static Future<Map<String, Map<String, PrayerStatus>>> dayPrayers(
      List<String> userIds, String date) async {
    if (userIds.isEmpty) return {};
    final rows = await supa
        .from('daily_prayers')
        .select()
        .eq('prayer_date', date)
        .inFilter('user_id', userIds);
    final out = <String, Map<String, PrayerStatus>>{};
    for (final r in rows) {
      out[r['user_id'] as String] = {
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
  static Future<List<String>> myPoolIds() async =>
      _poolIds ??= (await myPools()).map((p) => p.id).toList();

  /// Bir vakti kaydeder. Bugünse ve "kıldı/kılmadı" ise havuzlara olay düşer.
  static Future<void> setPrayer({
    required String key,
    required PrayerStatus status,
    String? date,
  }) async {
    final day = date ?? todayStr();
    await supa.from('daily_prayers').upsert(
      {'user_id': myId, 'prayer_date': day, key: status.code},
      onConflict: 'user_id,prayer_date',
    );
    if (day != todayStr()) return;
    final type = switch (status) {
      PrayerStatus.prayed => 'PRAYED',
      PrayerStatus.missed => 'MISSED',
      _ => null,
    };
    if (type == null) return;
    final pools = await myPoolIds();
    if (pools.isEmpty) return;
    // Tek istekte tüm havuzlara
    await supa.from('pool_events').insert([
      for (final p in pools)
        {'pool_id': p, 'sender_id': myId, 'event_type': type, 'prayer': key.toUpperCase()},
    ]);
  }

  /// Kendi namaz kayıtlarım (tarih aralığı, Karne için).
  static Future<Map<String, Map<String, PrayerStatus>>> myRange(DateTime from, DateTime to) async {
    String f(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
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
    final rows = await supa
        .from('kaza_prayers')
        .select('prayer_type, owed_count, completed_count')
        .eq('user_id', myId);
    return {
      for (final r in rows)
        r['prayer_type'] as String: (
          (r['owed_count'] as num).toInt(),
          (r['completed_count'] as num).toInt(),
        ),
    };
  }

  static Future<void> saveKaza(String type, int owed, int completed, {bool announce = false}) async {
    await supa.from('kaza_prayers').upsert({
      'user_id': myId,
      'prayer_type': type,
      'owed_count': owed,
      'completed_count': completed,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,prayer_type');
    if (!announce) return;
    final pools = await myPoolIds();
    if (pools.isEmpty) return;
    // Hangi vaktin kaza edildiği paylaşılmaz; sadece "kaza kıldı" olayı.
    await supa.from('pool_events').insert([
      for (final p in pools) {'pool_id': p, 'sender_id': myId, 'event_type': 'KAZA'},
    ]);
  }

  // ---- Olaylar ----
  static Stream<List<Map<String, dynamic>>> eventsStream(String poolId) => supa
      .from('pool_events')
      .stream(primaryKey: ['id'])
      .eq('pool_id', poolId)
      .order('created_at', ascending: false)
      .limit(50);

  static Future<void> sendDua(String poolId, String message) async {
    await supa.from('pool_events').insert({
      'pool_id': poolId,
      'sender_id': myId,
      'event_type': 'DUA',
      'message': message,
    });
  }
}
