import 'package:intl/intl.dart';
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

  static Future<void> leavePool(String poolId) =>
      supa.rpc('leave_pool', params: {'p_pool': poolId});

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
        .select('id, user_id, role_title, icon, profiles(display_name, email)')
        .eq('pool_id', poolId)
        .eq('status', 'pending')
        .order('created_at');
    return rows.map<JoinRequest>((r) => JoinRequest.fromMap(r)).toList();
  }

  static Future<void> approve(String requestId) =>
      supa.rpc('approve_join', params: {'p_request': requestId});

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

  /// Bugünkü bir vakti kaydeder; "kıldı/kılmadı" ise üye olduğum havuzlara olay düşer.
  static Future<void> setPrayer({
    required String key,
    required PrayerStatus status,
    required List<String> poolIds,
  }) async {
    await supa.from('daily_prayers').upsert(
      {'user_id': myId, 'prayer_date': todayStr(), key: status.code},
      onConflict: 'user_id,prayer_date',
    );
    final type = switch (status) {
      PrayerStatus.prayed => 'PRAYED',
      PrayerStatus.missed => 'MISSED',
      _ => null,
    };
    if (type == null) return;
    for (final p in poolIds) {
      await supa.from('pool_events').insert({
        'pool_id': p,
        'sender_id': myId,
        'event_type': type,
        'prayer': key.toUpperCase(),
      });
    }
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
