import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../content/daily_content.dart';
import '../data.dart';
import '../lang.dart';
import '../local_store.dart';
import '../member_icon.dart';
import '../models.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets/danger_box.dart';
import '../widgets/login_required.dart';
import '../widgets/prayer_icon.dart';

/// Aile Havuzu • İbadet Halkası.
/// Bir aile havuzunda en fazla kaç kişi olabilir (sunucuda da aynı sınır var).
const int kPoolMax = 5;

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  List<Pool> _pools = [];
  int _sel = 0;
  List<Member> _members = [];
  Map<String, Map<String, PrayerStatus>> _today = {};
  Map<String, Map<String, PrayerStatus>> _yesterday = {};
  Map<String, List<int>> _kaza = {};
  List<JoinRequest> _requests = [];
  List<(String, String, String, DateTime)> _outgoing = [];
  String _myName = '';
  bool _checkingLink = false;
  Timer? _ticker;
  bool _loading = true;
  bool _showYesterday = false;
  final _joinCtrl = TextEditingController();

  RealtimeChannel? _poolChannel;
  RealtimeChannel? _meChannel;
  String? _eventsPoolId;
  Timer? _debounce;

  int _idx(int len) => (_sel >= 0 && _sel < len) ? _sel : 0;
  Pool? get _pool => _pools.isEmpty ? null : _pools[_idx(_pools.length)];
  bool get _isOwner => _pool?.ownerId == myId;
  /// Bu kişinin BENİM ekranımdaki hitabı (akrabalığa göre: Kızın, Baban (Aile Reisi), Annen…).
  String _label(Member m) {
    final me = _members.where((x) => x.userId == myId).firstOrNull;
    final reis = _members.where((x) => x.userId == _pool?.ownerId).firstOrNull;
    if (me == null) return m.labelFor(viewerIsReis: _isOwner);
    return kinLabel(viewer: me, target: m, reis: reis);
  }

  @override
  void initState() {
    super.initState();
    if (isGuest) {
      _loadGuest();
      return;
    }
    _subscribeMe();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ticker?.cancel();
    _offlineRetry?.cancel();
    if (_poolChannel != null) supa.removeChannel(_poolChannel!);
    if (_meChannel != null) supa.removeChannel(_meChannel!);
    _joinCtrl.dispose();
    super.dispose();
  }

  void _refreshSoon([PostgresChangePayload? _]) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  /// Benim üyeliğim / isteğim değişince (onaylandım, reddedildim) yenile.
  void _subscribeMe() {
    final f = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: myId);
    _meChannel = supa
        .channel('me-$myId')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'pool_members', filter: f, callback: _refreshSoon)
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'join_requests', filter: f, callback: _refreshSoon)
        .subscribe();
  }

  /// Sadece değişen kişinin satırını günceller (tüm ekranı yeniden yüklemez).
  void _onPrayerChange(PostgresChangePayload p) {
    final r = p.newRecord;
    final uid = r['user_id'] as String?;
    final date = r['prayer_date'] as String?;
    if (uid == null || date == null || !_members.any((m) => m.userId == uid) || !mounted) return;
    final row = {for (final k in prayerKeys) k: PrayerStatusX.parse(r[k] as String?)};
    if (date == todayStr()) {
      setState(() => _today = {..._today, uid: row});
    } else if (date == _yStr()) {
      setState(() => _yesterday = {..._yesterday, uid: row});
    }
  }

  void _onKazaChange(PostgresChangePayload p) {
    final r = p.newRecord;
    final uid = r['user_id'] as String?;
    if (uid == null || !_members.any((m) => m.userId == uid) || !mounted) return;
    setState(() => _kaza = {
          ..._kaza,
          uid: [((r['owed'] ?? 0) as num).toInt(), ((r['completed'] ?? 0) as num).toInt()],
        });
  }

  void _subscribePool(String poolId) {
    if (_eventsPoolId == poolId) return;
    if (_poolChannel != null) supa.removeChannel(_poolChannel!);
    final f = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'pool_id', value: poolId);
    _poolChannel = supa
        .channel('pool-$poolId')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'daily_prayers', callback: _onPrayerChange)
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'pool_members', filter: f, callback: _refreshSoon)
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'join_requests', filter: f, callback: _refreshSoon)
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'kaza_summary', callback: _onKazaChange)
        .subscribe();
    _eventsPoolId = poolId;
  }

  String _yStr() => DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));

  Future<void> _load() async {
    if (isGuest) return _loadGuest();
    try {
      Repo.invalidatePools();
      var pools = await Repo.myPools().timeout(const Duration(seconds: 8));
      if (pools.isEmpty) {
        // Herkesin kendi havuzu ve davet kodu otomatik hazır
        await Repo.ensureMyPool();
        pools = await Repo.myPools();
        if (pools.isEmpty) throw Exception('pool');
      }
      final pool = pools[_idx(pools.length)];
      // Sıralama: önce kullanıcının kendisi, sonra Aile Reisi, sonra katılma sırası
      final members = [...await Repo.members(pool.id)]
        ..sort((x, y) {
          int rank(Member m) => m.userId == myId ? 0 : (m.userId == pool.ownerId ? 1 : 2);
          return rank(x).compareTo(rank(y));
        });
      final ids = members.map((m) => m.userId).toList();
      final solo = members.length <= 1;
      final r = await Future.wait<dynamic>([
        Repo.dayPrayers(ids, todayStr()),
        Repo.dayPrayers(ids, _yStr()),
        Repo.kazaSummary(ids),
        pool.ownerId == myId ? Repo.pendingRequests(pool.id) : Future.value(<JoinRequest>[]),
        solo ? Repo.myOutgoingRequests() : Future.value(<(String, String, String, DateTime)>[]),
        Repo.myDisplayName(),
      ]);
      if (!mounted) return;
      _subscribePool(pool.id);
      setState(() {
        _pools = pools;
        _members = members;
        _today = r[0] as Map<String, Map<String, PrayerStatus>>;
        _yesterday = r[1] as Map<String, Map<String, PrayerStatus>>;
        _kaza = r[2] as Map<String, List<int>>;
        _requests = r[3] as List<JoinRequest>;
        _outgoing = r[4] as List<(String, String, String, DateTime)>;
        _myName = r[5] as String;
        _loading = false;
        _offline = false;
      });
      _offlineRetry?.cancel();
      _offlineRetry = null;
      _syncTicker();
      unawaited(_saveSnapshot());
    } catch (_) {
      // İnternet yok: son bilinen aile durumunu göster, bağlantı gelince kendiliğinden yenile
      await _loadSnapshot();
      if (mounted) setState(() => _loading = false);
      _offlineRetry ??= Timer.periodic(const Duration(seconds: 15), (_) => _load());
    }
  }

  // ---------- Çevrimdışı: son bilinen aile durumu (telefonda) ----------
  bool _offline = false;
  Timer? _offlineRetry;

  static Map<String, String> _codes(Map<String, PrayerStatus> m) => {for (final e in m.entries) e.key: e.value.code};

  Future<void> _saveSnapshot() async {
    final pool = _pool;
    if (pool == null) return;
    final snap = {
      'date': todayStr(),
      'pool': {'id': pool.id, 'name': pool.name, 'owner_id': pool.ownerId, 'invite_code': pool.inviteCode},
      'members': [
        for (final m in _members)
          {'user_id': m.userId, 'name': m.name, 'role_title': m.roleTitle, 'icon': m.icon, 'gender': m.gender},
      ],
      'today': {for (final e in _today.entries) e.key: _codes(e.value)},
      'yesterday': {for (final e in _yesterday.entries) e.key: _codes(e.value)},
      'kaza': _kaza,
      'myName': _myName,
    };
    await AppSettings.prefs.setString('familySnapshot', jsonEncode(snap));
  }

  Future<void> _loadSnapshot() async {
    final raw = AppSettings.prefs.getString('familySnapshot');
    if (raw == null || !mounted) return;
    try {
      final s = jsonDecode(raw) as Map<String, dynamic>;
      Map<String, Map<String, PrayerStatus>> days(Object? v) => {
            for (final e in ((v ?? {}) as Map<String, dynamic>).entries)
              e.key: {
                for (final p in (e.value as Map<String, dynamic>).entries) p.key: PrayerStatusX.parse(p.value as String?)
              },
          };
      final sameDay = s['date'] == todayStr();
      final p = s['pool'] as Map<String, dynamic>;
      setState(() {
        _offline = true;
        _pools = [Pool.fromMap(p)];
        _members = [
          for (final m in (s['members'] as List).cast<Map<String, dynamic>>())
            Member(
                userId: m['user_id'],
                name: m['name'] ?? '',
                roleTitle: m['role_title'] ?? 'Aile Ferdi',
                icon: m['icon'] ?? '👥',
                gender: m['gender'] as String?),
        ];
        // Gün değiştiyse dünkü tablo = kaydedilen "bugün"
        _today = sameDay ? days(s['today']) : {};
        _yesterday = sameDay ? days(s['yesterday']) : days(s['today']);
        // Kendi işaretlerim her zaman telefondaki en güncel hâliyle
        _today = {..._today, myId: LocalStore.day(todayStr())};
        _yesterday = {..._yesterday, myId: LocalStore.day(_yStr())};
        _kaza = {
          for (final e in ((s['kaza'] ?? {}) as Map<String, dynamic>).entries)
            e.key: (e.value as List).map((x) => (x as num).toInt()).toList(),
        };
        _myName = s['myName'] as String? ?? '';
      });
    } catch (_) {}
  }

  // ---------- Gezinti (misafir) modu: yalnızca bakmak için, kayıt yapılmaz ----------

  Future<void> _loadGuest() async {
    final me = Member(userId: myId, name: t('Misafir', 'Guest'), roleTitle: 'Aile Ferdi', icon: '👤');
    final pool = Pool(id: 'local', name: t('Aile İbadet Havuzum', 'My Family Worship Circle'), ownerId: myId, inviteCode: 'EMB-······');
    final td = await Repo.dayPrayers([myId], todayStr());
    final y = await Repo.dayPrayers([myId], _yStr());
    if (!mounted) return;
    setState(() {
      _pools = [pool];
      _members = [me];
      _myName = t('Misafir', 'Guest');
      _today = td;
      _yesterday = y;
      _loading = false;
    });
  }

  /// Bulut gerektiren işlemlerde giriş penceresi.
  Future<void> _needLogin(String what) => showLoginRequired(context, what);

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Bekleyen istek varsa geri sayım için saniyede bir yenile; süre dolunca listeyi tazele.
  void _syncTicker() {
    final active = _outgoing.isNotEmpty || _requests.isNotEmpty;
    if (!active) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final expired = [..._outgoing.map((o) => o.$4), ..._requests.map((r) => r.createdAt)]
          .any((t) => _left(t) == Duration.zero);
      if (expired) {
        _ticker?.cancel();
        _ticker = null;
        _load();
      } else {
        setState(() {});
      }
    });
  }

  static const _window = Duration(minutes: 5);
  Duration _left(DateTime? created) {
    final d = (created ?? DateTime.now()).add(_window).difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  String _mmss(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  /// "Bağlantıyı Teyit Et": sunucuya sorup havuz / istek durumunu bildirir.
  Future<void> _verifyLink() async {
    if (isGuest) return _needLogin(t('Aile bağlantısını sorgulamak', 'look up a family connection'));
    setState(() => _checkingLink = true);
    final before = _members.length;
    await _load();
    if (!mounted) return;
    setState(() => _checkingLink = false);
    if (_members.length > 1) {
      _toast(_members.length > before
          ? t('🎉 Bağlantı kuruldu! Aile havuzunda ${_members.length} kişisiniz.', '🎉 Connected! There are ${_members.length} of you in the family circle.')
          : t('🟢 Bağlantı aktif: ${_members.length} kişi aile havuzunda.', '🟢 Connection active: ${_members.length} people in the family circle.'));
    } else if (_outgoing.isNotEmpty) {
      _toast(t('⏳ Talebin hâlâ Aile Reisinin onayını bekliyor (${_mmss(_left(_outgoing.first.$4))} kaldı).', '⏳ Your request is still waiting for the head of family\'s approval (${_mmss(_left(_outgoing.first.$4))} left).'));
    } else if (_requests.isNotEmpty) {
      _toast(t('🔔 Onay bekleyen ${_requests.length} katılım isteğin var.', '🔔 You have ${_requests.length} join requests awaiting approval.'));
    } else {
      _toast(t('Henüz bağlı bir aile ferdi yok. Davet kodunu paylaş veya bir koda katıl.', 'No family member connected yet. Share your invite code or join with a code.'));
    }
  }

  String _err(Object e) {
    final s = e.toString();
    if (s.contains('already_member')) return t('Zaten bu havuzdasın.', 'You are already in this circle.');
    if (s.contains('too_many_attempts')) return t('Çok fazla deneme. Biraz sonra tekrar dene.', 'Too many attempts. Try again a bit later.');
    if (s.contains('request_expired')) return t('İsteğin 5 dakikalık onay süresi doldu. Tekrar istek gönderebilirsin.', 'Your request\'s 5-minute approval window expired. You can send a new request.');
    if (s.contains('rate_limited')) return t('Çok sık gönderdin. Biraz bekleyip tekrar dene.', 'You sent too often. Wait a little and try again.');
    if (s.contains('pending_exists')) return t('Zaten bekleyen bir katılım isteğin var. 5 dakika içinde onaylanmazsa yenisini gönderebilirsin.', 'You already have a pending join request. If it is not approved within 5 minutes you can send a new one.');
    if (s.contains('invalid_owner_role')) return t('Kendi ünvanın Aile Reisi, Baba veya Anne olabilir.', 'Your own title can be Head of Family, Father or Mother.');
    if (s.contains('pool_full')) return t('Bu aile havuzu dolu (en fazla $kPoolMax kişi).', 'This family circle is full (at most $kPoolMax people).');
    if (s.contains('already_in_family')) return t('Zaten bir aile havuzundasın. Önce mevcut havuzdan ayrılmalısın.', 'You are already in a family circle. Leave it first.');
    if (s.contains('owner_cannot_leave')) return t('Aile Reisi ayrılamaz; önce yöneticiliği devret.', 'The head of family cannot leave; hand over leadership first.');
    return t('İşlem yapılamadı. İnternet bağlantını kontrol et.', 'Could not complete. Check your internet connection.');
  }

  /// Yanlışlıkla basılmasın: tek pencerede iki ayrı onay kutusu işaretlenmeden düğme açılmaz.
  Future<bool> _doubleConfirm({
    required String title,
    required String text,
    required String first,
    required String second,
    required String yes,
  }) async {
    var a = false, b = false;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          icon: const Icon(Icons.warning_amber_rounded, color: AppColors.missed, size: 32),
          title: Text(title, style: const TextStyle(fontSize: 15)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: a,
              onChanged: (v) => setD(() => a = v ?? false),
              title: Text(t('1. onay: $first', 'Confirmation 1: $first'), style: const TextStyle(fontSize: 13)),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: b,
              onChanged: a ? (v) => setD(() => b = v ?? false) : null,
              title: Text(t('2. onay: $second', 'Confirmation 2: $second'), style: const TextStyle(fontSize: 13)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.missed),
              onPressed: a && b ? () => Navigator.pop(ctx, true) : null,
              child: Text(yes),
            ),
          ],
        ),
      ),
    );
    return r == true;
  }

  Future<bool?> _confirm(String text, {String? yes}) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes ?? t('Evet', 'Yes'))),
          ],
        ),
      );

  // ======================= Eylemler =======================

  Future<void> _join(String input) async {
    final v = input.trim();
    if (v.isEmpty) return;
    if (isGuest) return _needLogin(t('Bir aile havuzuna katılmak', 'join a family circle'));
    try {
      // Unvanı ve simgeyi onaylarken Aile Reisi belirler.
      final ok = await Repo.requestJoin(v, 'Aile Ferdi', '👥');
      if (!ok) {
        _toast(t('Davet kodu geçersiz. Aile Reisinden kodu tekrar iste.', 'Invalid invite code. Ask the head of family for the code again.'));
        return;
      }
      await _load();
    } catch (e) {
      // İnternet kesilmiş olabilir: istek sunucuya ulaştı mı kontrol et.
      // Ulaşmadıysa tekrar denenebilir; ulaştıysa 5 dk içinde onaylanmazsa kendiliğinden düşer.
      await _load();
      if (!mounted) return;
      if (_outgoing.isNotEmpty) {
        _toast(t('Talebin iletildi ⏳ Aile Reisinin onayı bekleniyor.', 'Request sent ⏳ Waiting for the head of family\'s approval.'));
      } else if (e.toString().contains('pending_exists') || e.toString().contains('rate_limited') ||
          e.toString().contains('already_member') || e.toString().contains('too_many_attempts')) {
        _toast(_err(e));
      } else {
        _toast(t('Talep iletilemedi. İnternet bağlantını kontrol edip tekrar dene.', 'Could not send the request. Check your internet connection and try again.'));
      }
    }
  }

  Future<void> _approve(JoinRequest r) async {
    final who = r.name.isNotEmpty ? r.name : t('Bir aile ferdi', 'A family member');
    final me = _members.where((m) => m.userId == myId).firstOrNull;
    final res = await showDialog<_TitleResult>(
      context: context,
      builder: (_) => _TitleDialog(
        initialOwnerGender: me?.gender,
        title: t('🤝 $who havuzuna katılmak istiyor', '🤝 $who wants to join your circle'),
        subtitle: t('Sana göre unvanını ve simgesini seç:', 'Choose their title (relative to you) and icon:'),
        initialTitle: 'Aile Ferdi',
        initialIcon: '👥',
        confirm: t('Onayla & Havuza Ekle', 'Approve & Add to Circle'),
        askOwner: true,
        initialOwner: ownerTitles.containsKey(_myRole) ? _myRole : 'Aile Reisi',
      ),
    );
    if (res == null) return;
    try {
      await Repo.approveWithRoles(r.id,
          memberRole: res.title,
          memberIcon: res.icon,
          ownerRole: res.owner,
          ownerIcon: ownerTitles[res.owner],
          memberGender: res.gender,
          ownerGender: res.ownerGender);
      _toast(t('🎉 ${titleFor(res.title, viewerIsReis: true)} aile havuzuna katıldı!',
          '🎉 ${titleFor(res.title, viewerIsReis: true)} joined the family circle!'));
      await _load();
    } catch (e) {
      _toast(_err(e));
    }
  }

  String get _myRole => _members.where((m) => m.userId == myId).firstOrNull?.roleTitle ?? 'Aile Ferdi';

  Future<void> _sendDua({Member? to}) async {
    if (isGuest) return _needLogin(t('Dua göndermek', 'send a prayer (dua)'));
    final text = await showDialog<String>(context: context, builder: (_) => _DuaDialog(to: to == null ? null : _label(to)));
    if (text == null || _pool == null) return;
    // Hazır dua seçildiyse boş gider: her alıcı onu kendi dilinde görür (sunucu ve uygulama doldurur)
    final msg = text == _kDuaDefault ? '' : text.trim();
    if (msg.isEmpty && text != _kDuaDefault) return;
    try {
      await Repo.sendDua(_pool!.id, msg.length > 280 ? msg.substring(0, 280) : msg, targetId: to?.userId);
      _toast(to == null ? t('Dua tüm aileye gönderildi 🤲', 'Dua sent to the whole family 🤲') : t('Dua yalnızca ona gönderildi 🤲 (${_label(to)})', 'Dua sent only to them 🤲 (${_label(to)})'));
    } catch (e) {
      _toast(_err(e));
    }
  }

  Future<void> _memberAction(Member m, String action) async {
    if (isGuest) return _needLogin(t('Üye yönetimi', 'manage members'));
    final pool = _pool;
    if (pool == null) return;
    try {
      switch (action) {
        case 'role':
          final res = await showDialog<_TitleResult>(
            context: context,
            builder: (_) => _TitleDialog(
              title: m.name.isNotEmpty ? m.name : _label(m),
              subtitle: t('Sana göre unvanı ve simgesi:', 'Their title (relative to you) and icon:'),
              initialTitle: m.roleTitle,
              initialIcon: m.icon,
              initialGender: m.gender,
              confirm: t('Kaydet', 'Save'),
            ),
          );
          if (res == null) return;
          await Repo.setMemberRole(pool.id, m.userId, res.title, res.icon, gender: res.gender);
        case 'owner':
          if (await _confirm(t('Aile Reisliği ${_label(m)} kişisine devredilsin mi? Bunu geri alamazsın.', 'Hand over leadership of the family to ${_label(m)}? You cannot undo this.')) != true) return;
          await Repo.transferOwnership(pool.id, m.userId);
        case 'remove':
          if (await _confirm(t('${_label(m)} havuzdan çıkarılsın mı?', 'Remove ${_label(m)} from the circle?')) != true) return;
          await Repo.removeMember(pool.id, m.userId);
      }
      await _load();
    } catch (e) {
      _toast(_err(e));
    }
  }

  // ======================= Arayüz =======================

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final pool = _pool;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (isGuest) ...[_guestBanner(), const SizedBox(height: 12)],
          if (_offline && !isGuest) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.goldContainer, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.wifi_off, color: Color(0xFF78350F), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(t('İnternet yok: ailenin son bilinen durumu gösteriliyor. Bağlantı gelince kendiliğinden yenilenir.', 'No internet: showing your family\'s last known status. It refreshes automatically when online.'),
                      style: TextStyle(fontSize: 12, color: Color(0xFF78350F))),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          if (!isGuest) ...[_profileCard(), const SizedBox(height: 12)],
          _hero(),
          const SizedBox(height: 12),
          if (pool != null) ...[
            if (_members.length <= 1) ...[
              _codeCard(pool),
              const SizedBox(height: 12),
              if (_outgoing.isNotEmpty) _pendingCard() else _joinCard(),
              const SizedBox(height: 12),
            ],
            for (final r in _requests) ...[_requestCard(r), const SizedBox(height: 10)],
            if (_members.length > 1) ...[
              _isOwner ? _codeCard(pool) : _memberStatusCard(pool),
              const SizedBox(height: 12),
            ],
            _matrix(),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.emerald,
                side: const BorderSide(color: AppColors.cardBorder),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => _sendDua(),
              icon: const Text('🤲'),
              label: Text(t('Aileye Dua Gönder', 'Send a Dua to the Family'), style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            _membersSection(),
            const SizedBox(height: 16),
            if (_isOwner && _members.length > 1)
              DangerBox(
                title: t('Havuzu Kapat & Sıfırla', 'Close & Reset Circle'),
                subtitle: t('Tüm üyeler havuzdan çıkarılır', 'All members are removed from the circle'),
                onTap: () async {
                  if (!await _doubleConfirm(
                    title: t('Havuzu Kapat & Sıfırla', 'Close & Reset Circle'),
                    text: t(
                        'Havuz kapatılırsa bütün aile fertleri havuzdan çıkarılır; ünvanlar, dua ve hareket kayıtları silinir. '
                            'Herkesin kendi namaz ve kaza kayıtları kendi hesabında kalır.',
                        'If the circle is closed, all family members are removed; titles, duas and activity records are deleted. '
                            "Everyone's own prayer and kaza records stay in their own account."),
                    first: t('Tüm üyelerin havuzdan çıkarılacağını anladım', 'I understand all members will be removed'),
                    second: t('Havuzu kapatmak istiyorum', 'I want to close the circle'),
                    yes: t('Havuzu Kapat', 'Close Circle'),
                  )) {
                    return;
                  }
                  try {
                    await Repo.deletePool(pool.id);
                    _sel = 0;
                    await _load();
                  } catch (e) {
                    _toast(_err(e));
                  }
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _hero() {
    final pool = _pool;
    final white85 = Colors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(color: AppColors.emerald, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 14)),
            SizedBox(width: 6),
            Text(t('AİLE HAVUZU • İBADET HALKASI', 'FAMILY CIRCLE • WORSHIP CIRCLE'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
          ]),
          const SizedBox(height: 10),
          Text(
            pool == null
                ? t('Aile havuzun hazırlanıyor…', 'Preparing your family circle…')
                : _members.length <= 1
                    ? t('Davet kodunu ailenle paylaş; katıldıkça burada görünecekler.', 'Share the invite code with your family; they will appear here as they join.')
                    : t('${_members.length} kişi • Aile Havuzunda Bağlı 🟢 Aktif', '${_members.length} people • Connected in the Family Circle 🟢 Active'),
            style: TextStyle(fontSize: 13, color: white85),
          ),
          if (_pools.length > 1) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (var i = 0; i < _pools.length; i++)
                ChoiceChip(
                  label: Text(_pools[i].displayName),
                  selected: i == _sel,
                  onSelected: (_) {
                    setState(() => _sel = i);
                    _load();
                  },
                ),
            ]),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _members.length > 1 ? AppColors.prayedMint : AppColors.goldContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_members.length > 1 ? t('🟢 AKTİF', '🟢 ACTIVE') : t('⏳ BEKLEMEDE', '⏳ PENDING'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _members.length > 1 ? AppColors.emeraldDark : const Color(0xFF78350F))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_members.length > 1 ? t('Bağlantı Kuruldu ✓', 'Connected ✓') : t('Bağlantı Bekleniyor ⏳', 'Waiting for Connection ⏳'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _checkingLink ? null : _verifyLink,
              icon: _checkingLink
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('🔄'),
              label: Text(_checkingLink ? t('Sorgulanıyor…', 'Checking…') : t('Bağlantıyı Teyit Et', 'Verify Connection'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          Text('"Ailene namazı emret ve kendin de onda devamlı ol." (Tâhâ, 132)',
              style: TextStyle(fontSize: 11, color: white85, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  /// Gezinti modu: tek satır sade uyarı; dokununca giriş penceresi açılır.
  Widget _guestBanner() => Material(
        color: AppColors.goldContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => LocalStore.setGuestMode(false),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF78350F)),
              SizedBox(width: 8),
              Expanded(
                child: Text(t('Gezinti modundasın · Ailene bağlanmak için giriş yap', 'You are browsing · Sign in to connect with your family'),
                    style: TextStyle(fontSize: 13, color: Color(0xFF78350F), fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.chevron_right, color: Color(0xFF78350F)),
            ]),
          ),
        ),
      );

  Widget _profileCard() {
    final family = _members.length > 1;
    final me = _members.where((m) => m.userId == myId).firstOrNull;
    return _whiteCard(
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.emeraldContainer,
          child: MemberIcon(me?.icon ?? '👤', size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_myName.isNotEmpty ? _myName : roleText('Aile Ferdi'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            Text('${roleText(me?.roleTitle ?? 'Aile Ferdi')} · ${isGuest ? t('Gezinti modu (giriş yapılmadı)', 'Browsing mode (not signed in)') : t('Google Hesabı Bağlı ✓', 'Google Account Connected ✓')}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: family ? AppColors.emerald : AppColors.emeraldContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(family ? t('Aile Modu', 'Family Mode') : t('Bireysel Mod', 'Individual Mode'),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: family ? Colors.white : AppColors.emerald)),
        ),
      ]),
    );
  }

  Widget _countdown(DateTime? created, Color color) {
    final left = _left(created);
    return Row(children: [
      Icon(Icons.timer_outlined, size: 16, color: color),
      const SizedBox(width: 4),
      Text(t('Onay için kalan süre: ${_mmss(left)}', 'Time left for approval: ${_mmss(left)}'),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      const SizedBox(width: 8),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: left.inSeconds / _window.inSeconds,
            minHeight: 5,
            color: color,
            backgroundColor: color.withValues(alpha: 0.2),
          ),
        ),
      ),
    ]);
  }

  Widget _whiteCard({required Widget child, Color? color}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color ?? AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: child,
      );

  Widget _joinCard() {
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.emeraldLight, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('📥', style: TextStyle(fontSize: 15)),
              SizedBox(width: 6),
              Expanded(
                child: Text(t('Başka Bir Aile Havuzuna Katıl', 'Join Another Family Circle'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.goldContainer)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(t('Aile Reisin sen değilsen, onun sana ilettiği davet kodunu gir:', 'If you are not the head of family, enter the invite code they gave you:'),
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9))),
            const SizedBox(height: 10),
            TextField(
              controller: _joinCtrl,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: t('Örn: EMB-123456', 'e.g. EMB-123456'),
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            Text(t('Katıldıktan sonra ünvanını (Eşi, Oğlu, Kızı…) ve simgeni Aile Reisi belirler.', 'After you join, the head of family sets your title (Spouse, Son, Daughter…) and icon.'),
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.emerald),
                onPressed: () => _join(_joinCtrl.text),
                child: Text(t('Havuza Katıl', 'Join Circle'), style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
  }

  Widget _pendingCard() {
    final (id, poolName, ownerName, created) = _outgoing.first;
    return _whiteCard(
      color: AppColors.goldContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('⏳', style: TextStyle(fontSize: 15)),
            SizedBox(width: 8),
            Text(t('Katılım Talebi İletildi', 'Join Request Sent'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF78350F))),
          ]),
          const SizedBox(height: 6),
          Text(
            t(
                '"$poolName" havuzuna katılma isteğin ${ownerName.isNotEmpty ? '$ownerName adlı ' : ''}Aile Reisine iletildi. '
                    'Onaylayıp ünvanını belirlediğinde havuz burada açılacak. '
                    'Talep 5 dakika içinde onaylanmalıdır; bu sürede başka talep gönderemezsin.',
                'Your request to join "$poolName" was sent to the head of family${ownerName.isNotEmpty ? ' ($ownerName)' : ''}. '
                    'The circle opens here once they approve it and set your title. '
                    'The request must be approved within 5 minutes; you cannot send another one meanwhile.'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.35),
          ),
          const SizedBox(height: 8),
          _countdown(created, const Color(0xFF92400E)),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () async {
              try {
                await Repo.cancelRequest(id);
                await _load();
              } catch (e) {
                _toast(_err(e));
              }
            },
            child: Text(t('Talebi İptal Et', 'Cancel Request')),
          ),
        ],
      ),
    );
  }

  Widget _requestCard(JoinRequest r) => _whiteCard(
        color: AppColors.goldContainer,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('🔔', style: TextStyle(fontSize: 15)),
              SizedBox(width: 8),
              Expanded(
                child: Text(t('Aşağıdaki aile ferdin havuzuna dahil olmak istiyor:', 'This family member wants to join your circle:'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF78350F))),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              MemberIcon(r.icon, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name.isNotEmpty ? r.name : t('Bir aile ferdi', 'A family member'),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  Text(t('Onaylarken ünvanını ve simgesini sen belirleyeceksin.', 'You will set their title and icon when approving.'),
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            _countdown(r.createdAt, const Color(0xFF92400E)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
                  onPressed: () => _approve(r),
                  child: Text(t('Onayla & Rol Seç', 'Approve & Choose Role')),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.missed),
                onPressed: () async {
                  try {
                    await Repo.reject(r.id);
                    await _load();
                  } catch (e) {
                    _toast(_err(e));
                  }
                },
                child: Text(t('Reddet', 'Decline')),
              ),
            ]),
          ],
        ),
      );

  Widget _codeCard(Pool pool) {
    if (_members.length >= kPoolMax) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.emeraldLight, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Text('🏡', style: TextStyle(fontSize: 22)),
          SizedBox(width: 10),
          Expanded(
            child: Text(t('Havuz dolu ($kPoolMax/$kPoolMax). Yeni kişi eklemek için önce bir üyeyi çıkarmalısın.', 'The circle is full ($kPoolMax/$kPoolMax). Remove a member to add someone new.'),
                style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.emeraldLight, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('Davet Kodunuzu Paylaşın 🔗', 'Share Your Invite Code 🔗'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          Text(t('Aile Havuz Paylaşım Kodun', 'Your Family Circle Invite Code'),
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(pool.displayCode,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
            ),
            IconButton(
              tooltip: t('Paylaş', 'Share'),
              onPressed: () async {
                if (isGuest) return _needLogin(t('Davet kodu oluşturmak', 'create an invite code'));
                await Share.share(
                  t(
                      '🕌 Aile ile Namaz uygulamasında aile havuzumuza katıl!\n\n'
                          'Davet kodu: ${pool.displayCode}\n'
                          '(Kodu 5 dakika içinde onaylarım.)\n\n'
                          'Uygulama: https://github.com/bilkil53/aile-ile-namaz-/releases/latest/download/aile-ile-namaz.apk',
                      '🕌 Join our family circle in the Aile ile Namaz app!\n\n'
                          'Invite code: ${pool.displayCode}\n'
                          '(I will approve it within 5 minutes.)\n\n'
                          'App: https://github.com/bilkil53/aile-ile-namaz-/releases/latest/download/aile-ile-namaz.apk'),
                  subject: t('Aile Havuzu davet kodu', 'Family Circle invite code'),
                );
              },
              icon: const Icon(Icons.share, color: Colors.white),
            ),
            IconButton(
              tooltip: t('Kopyala', 'Copy'),
              onPressed: () async {
                if (isGuest) return _needLogin(t('Davet kodu oluşturmak', 'create an invite code'));
                await Clipboard.setData(ClipboardData(text: pool.displayCode));
                _toast(t('Kod kopyalandı: ${pool.displayCode}', 'Code copied: ${pool.displayCode}'));
              },
              icon: const Icon(Icons.copy, color: Colors.white),
            ),
            IconButton(
              tooltip: t('Yeni kod', 'New code'),
              onPressed: () async {
                if (isGuest) return _needLogin(t('Davet kodu oluşturmak', 'create an invite code'));
                if (await _confirm(t('Eski kod geçersiz olacak. Yeni kod üretilsin mi?', 'The old code will stop working. Create a new code?')) != true) return;
                try {
                  await Repo.regenerateCode(pool.id);
                  await _load();
                } catch (e) {
                  _toast(_err(e));
                }
              },
              icon: const Icon(Icons.refresh, color: Colors.white),
            ),
          ]),
          Text(
            t(
                'Bu kodu ailenle paylaş. Katılmak istediklerinde burada onay kartı açılır; '
                    'onaylarken ona sana göre ünvanını (Eşi, Oğlu, Kızı…) ve simgesini verirsin.',
                'Share this code with your family. When they want to join, an approval card opens here; '
                    'while approving you give them a title relative to you (Spouse, Son, Daughter…) and an icon.'),
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85), height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _memberStatusCard(Pool pool) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _whiteCard(
          child: Row(children: [
            Text('🕌', style: TextStyle(fontSize: 24)),
            SizedBox(width: 10),
            Expanded(
              child: Text(t('Aile İbadet Havuzundasın', 'You are in a Family Worship Circle'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        DangerBox(
          title: t('Havuzdan Ayrıl', 'Leave Circle'),
          subtitle: t('Ailenin namaz durumunu artık göremezsin', 'You will no longer see your family\'s prayers'),
          icon: Icons.logout,
          onTap: () async {
              if (!await _doubleConfirm(
                title: t('Havuzdan Ayrıl', 'Leave Circle'),
                text: t(
                    'Ayrılırsan ailen senin namaz durumunu artık göremez, sen de onlarınkini göremezsin. '
                        'Kendi namaz ve kaza kayıtların hesabında kalır. Tekrar katılmak için Aile Reisinden yeni onay gerekir.',
                    'If you leave, your family can no longer see your prayers and you cannot see theirs. '
                        'Your own prayer and kaza records stay in your account. Rejoining needs new approval from the head of family.'),
                first: t('Ailemin durumunu artık göremeyeceğimi anladım', 'I understand I will no longer see my family\'s status'),
                second: t('Havuzdan ayrılmak istiyorum', 'I want to leave the circle'),
                yes: t('Evet, Ayrıl', 'Yes, Leave'),
              )) {
                return;
              }
              try {
                await Repo.leavePool(pool.id);
                _sel = 0;
                await _load();
              } catch (e) {
                _toast(_err(e));
              }
          },
        ),
      ]);

  // ---------- Ortak matris (vakit × kişi) ----------
  Widget _matrix() {
    final data = _showYesterday ? _yesterday : _today;
    const colW = 78.0;
    Widget toggle(String label, bool sel, bool yesterday) => GestureDetector(
          onTap: () => setState(() => _showYesterday = yesterday),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: sel ? Colors.white : Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: sel ? AppColors.emerald : Colors.white)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.emerald, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('👨‍👩‍👧', style: TextStyle(fontSize: 17)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(t('Aile İbadet Halkası', 'Family Worship Circle'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            toggle(t('◄ Dünü Gör', '◄ See Yesterday'), _showYesterday, true),
            const SizedBox(width: 6),
            toggle(t('Bugün', 'Today'), !_showYesterday, false),
          ]),
          const SizedBox(height: 4),
          Builder(builder: (_) {
            final total = _members.length * prayerKeys.length;
            final done = [
              for (final m in _members)
                for (final k in prayerKeys)
                  if (data[m.userId]?[k] == PrayerStatus.prayed) 1
            ].length;
            final pct = total == 0 ? 0 : (done * 100 / total).round();
            return Container(
              margin: const EdgeInsets.only(top: 6, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Text('🏆', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      _showYesterday
                          ? t('Dün Aile Başarısı: $done / $total Vakit', "Yesterday's Family Success: $done / $total prayers")
                          : t('Bugün Aile Başarısı: $done / $total Vakit', "Today's Family Success: $done / $total prayers"),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                Text(t('%$pct', '$pct%'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.prayedMint)),
              ]),
            );
          }),
          Row(children: [
            Text(t('ORTAK MATRİS', 'SHARED GRID'),
                style: TextStyle(fontSize: 10, letterSpacing: 1, color: Colors.white.withValues(alpha: 0.7))),
            const Spacer(),
            if (_members.length > 3)
              Text(t('Sağa Kaydırılabilir (${_members.length} Kişi) →', 'Scroll right (${_members.length} people) →'),
                  style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.7))),
          ]),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  SizedBox(
                    width: 72,
                    child: Text(t('VAKİT', 'PRAYER'),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.7))),
                  ),
                  for (final m in _members)
                    SizedBox(
                      width: colW,
                      child: Column(children: [
                        MemberIcon(m.icon, size: 18),
                        Text(m.userId == myId ? t('Sen', 'You') : _label(m),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                      ]),
                    ),
                ]),
                const SizedBox(height: 6),
                for (final k in prayerKeys)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(
                        width: 72,
                        child: Row(children: [
                          PrayerIcon(k, size: 14, color: Colors.white.withValues(alpha: 0.8)),
                          const SizedBox(width: 5),
                          Text(prayerLabels[k]!,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                        ]),
                      ),
                      for (final m in _members)
                        SizedBox(width: colW, child: Center(child: _cell(data[m.userId]?[k] ?? PrayerStatus.none))),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(PrayerStatus s) {
    final (label, bg, fg) = switch (s) {
      PrayerStatus.prayed => (t('Kıldı', 'Prayed'), Colors.white, AppColors.emerald),
      PrayerStatus.missed => (t('Kılmadı', 'Missed'), AppColors.missed, Colors.white),
      PrayerStatus.excused => (t('Muaf', 'Excused'), Colors.white.withValues(alpha: 0.25), Colors.white),
      PrayerStatus.none => ('—', Colors.transparent, Colors.white.withValues(alpha: 0.45)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: null,
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  // ---------- Bireyler ----------
  Widget _membersSection() {
    final pool = _pool!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(t('Havuzdaki Bireyler ve Durumları', 'Circle Members and Their Status'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ),
          Text(t('👥 ${_members.length}/$kPoolMax kişi', '👥 ${_members.length}/$kPoolMax people'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 8),
        for (final m in _members) ...[
          _memberCard(m, pool),
          const SizedBox(height: 8),
        ],
        if (_members.length == 1)
          Padding(
            padding: EdgeInsets.all(8),
            child: Text(t('Aile fertlerin davet kodun ile havuza dahil oldukça burada listelenecek ⏳', 'Family members will be listed here as they join with your invite code ⏳'),
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
      ],
    );
  }

  Widget _memberCard(Member m, Pool pool) {
    final isOwner = m.userId == pool.ownerId;
    final isMe = m.userId == myId;
    final day = _today[m.userId] ?? {};
    final prayed = prayerKeys.where((k) => day[k] == PrayerStatus.prayed).length;
    final kaza = _kaza[m.userId];
    final kazaLeft = kaza == null ? 0 : (kaza[0] - kaza[1]).clamp(0, 999999).toInt();
    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            MemberIcon(m.icon, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isMe ? t('${roleText(m.shownName)} (sen)', '${roleText(m.shownName)} (you)') : _label(m),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                Text(isOwner ? t('• 🏡 Havuz Yöneticisi', '• 🏡 Circle Admin') : t('• 👥 Aile Ferdi', '• 👥 Family Member'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isOwner ? AppColors.gold : AppColors.emerald)),
                if (m.name.isNotEmpty && m.name != m.shownName && m.name != _label(m))
                  Text(m.name, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: AppColors.emeraldContainer, borderRadius: BorderRadius.circular(8)),
              child: Text('$prayed/5',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.emerald)),
            ),
            if (_isOwner && !isMe)
              PopupMenuButton<String>(
                onSelected: (v) => _memberAction(m, v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'role', child: Text(t('Ünvan / simge belirle', 'Set title / icon'))),
                  PopupMenuItem(value: 'owner', child: Text(t('Aile Reisi yap', 'Make head of family'))),
                  PopupMenuItem(value: 'remove', child: Text(t('Havuzdan çıkar', 'Remove from circle'))),
                ],
              ),
          ]),
          if (kazaLeft > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.goldContainer, borderRadius: BorderRadius.circular(8)),
              child: Text(t('📿 Kaza: $kazaLeft kaldı • ${kaza![1]} eda edildi', '📿 Kaza: $kazaLeft left • ${kaza[1]} made up'),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF78350F))),
            ),
          ],
          if (!isMe) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => _sendDua(to: m),
              icon: const Text('👏'),
              label: Text(t('Tebrik Et & Dua Gönder', 'Congratulate & Send Dua'),
                  style: TextStyle(color: AppColors.emerald, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

}

// ======================= Diyaloglar =======================

/// Aile Reisinin kullandığı ünvan + simge seçici (ünvanlar reise göre).
class _TitleResult {
  final String title, icon;
  final String? owner, gender, ownerGender;
  const _TitleResult(this.title, this.icon, this.owner, this.gender, this.ownerGender);
}

class _TitleDialog extends StatefulWidget {
  final String? initialGender;
  final String? initialOwnerGender;
  final String title;
  final String subtitle;
  final String initialTitle;
  final String initialIcon;
  final String confirm;
  final bool askOwner;
  final String initialOwner;
  const _TitleDialog({
    required this.title,
    required this.subtitle,
    required this.initialTitle,
    required this.initialIcon,
    required this.confirm,
    this.askOwner = false,
    this.initialOwner = 'Aile Reisi',
    this.initialGender,
    this.initialOwnerGender,
  });

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late String _title = widget.initialTitle;
  late String _icon = widget.initialIcon;
  late String _owner = widget.initialOwner;

  static String? _genderOf(String title) =>
      femaleTitles.contains(title) ? 'f' : (maleTitles.contains(title) ? 'm' : null);

  /// Cinsiyet ayrıca seçilmez: simgeden çıkar (kadın/kız simgesi → Muaf açılır).
  /// Nötr simgede (🧒, 👤…) ünvandan, o da yoksa önceki kayıttan alınır.
  String? get _gender => genderOfIcon(_icon) ?? _genderOf(_title) ?? widget.initialGender;

  /// Reisin kendisi: Anne → kadın, Baba → erkek, Aile Reisi → önceki kayıt (yoksa erkek).
  String? get _ownerGender =>
      _owner == 'Anne' ? 'f' : (_owner == 'Baba' ? 'm' : (widget.initialOwnerGender ?? 'm'));

  late final _ctrl =
      TextEditingController(text: reisTitles.containsKey(widget.initialTitle) ? '' : widget.initialTitle);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final custom = _ctrl.text.trim();
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 15)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.askOwner) ...[
              Text(t('Senin ünvanın', 'Your title'), style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final e in ownerTitles.entries)
                  ChoiceChip(
                    label: Text('${e.value} ${roleText(e.key)}'),
                    selected: _owner == e.key,
                    onSelected: (_) => setState(() => _owner = e.key),
                  ),
              ]),
              const Divider(height: 22),
            ],
            Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Text(t('Ünvanı (sana göre)', 'Their title (relative to you)'), style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in reisTitles.entries)
                ChoiceChip(
                  label: Text('${e.value} ${titleFor(e.key, viewerIsReis: true)}'),
                  selected: custom.isEmpty && _title == e.key,
                  onSelected: (_) => setState(() {
                    _ctrl.clear();
                    _title = e.key;
                    _icon = e.value;
                  }),
                ),
            ]),
            TextField(
              controller: _ctrl,
              maxLength: 30,
              decoration: InputDecoration(labelText: t('Veya ismini yaz (örn. Ahmet)', 'Or type their name (e.g. Ahmet)')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            Text(t('Simgesi', 'Icon'), style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(t('Kadın ve kız simgelerinde "Muaf" seçeneği otomatik açılır.', 'For woman and girl icons the "Excused" option is enabled automatically.'),
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            for (final g in iconGroups.entries) ...[
              const SizedBox(height: 6),
              Text(iconGroupText(g.key), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: [
                for (final ic in g.value)
                  GestureDetector(
                    onTap: () => setState(() => _icon = ic),
                    child: Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _icon == ic ? AppColors.emeraldContainer : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _icon == ic ? AppColors.emerald : AppColors.cardBorder, width: 1.5),
                      ),
                      child: MemberIcon(ic, size: 22),
                    ),
                  ),
              ]),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Vazgeç', 'Cancel'))),
        FilledButton(
          onPressed: () => Navigator.pop(
              context,
              _TitleResult(custom.isNotEmpty ? custom : _title, _icon, widget.askOwner ? _owner : null, _gender,
                  widget.askOwner ? _ownerGender : null)),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

/// Dua ve tebrik gönder: hazır dualar + kendin yaz.
/// "Hazır duayı gönder" seçimi: mesaj boş gönderilir, her alıcı hazır duayı kendi dilinde görür.
const _kDuaDefault = '\u0000default';

class _DuaDialog extends StatefulWidget {
  final String? to;
  const _DuaDialog({this.to});

  @override
  State<_DuaDialog> createState() => _DuaDialogState();
}

class _DuaDialogState extends State<_DuaDialog> {
  final _ctrl = TextEditingController();
  static String get _defaultDua => t('Allah ibadetlerimizi kabul etsin, ailemizi namazda buluştursun 🤲',
      'May Allah accept our worship and unite our family in prayer 🤲');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.to == null ? t('🤲 Dua ve Tebrik Gönder', '🤲 Send Dua and Greetings') : t('🤲 ${widget.to} için dua', '🤲 Dua for ${widget.to}'),
          style: const TextStyle(fontSize: 15)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('Hazır manevi dualar ve tebrikler:', 'Ready-made duas and greetings:'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            for (final g in greetings)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  dense: true,
                  leading: Text(g.emoji, style: const TextStyle(fontSize: 17)),
                  title: Text(g.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text(g.text, style: const TextStyle(fontSize: 12)),
                  onTap: () => Navigator.pop(context, g.text),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              onChanged: (_) => setState(() {}),
              controller: _ctrl,
              maxLength: 240,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: t('Veya kendi duanı yaz', 'Or write your own dua'),
                hintText: t('Örn: Allah kabul etsin, hayırlı ve bereketli olsun…', 'e.g. May Allah accept it, may it be blessed…'),
              ),
            ),
            if (_ctrl.text.trim().isEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.emeraldContainer, borderRadius: BorderRadius.circular(10)),
                child: Text(t('Bir şey yazmazsan şu dua gönderilir:\n"$_defaultDua"', 'If you leave it empty, this dua is sent:\n"$_defaultDua"'),
                    style: TextStyle(fontSize: 12, color: AppColors.emerald)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Vazgeç', 'Cancel'))),
        FilledButton(
          // Boş bırakılırsa gönderilecek dua önizlemede yazar
          onPressed: () => Navigator.pop(context, _ctrl.text.trim().isEmpty ? _kDuaDefault : _ctrl.text),
          child: Text(_ctrl.text.trim().isEmpty ? t('Hazır duayı gönder 🤲', 'Send the ready-made dua 🤲') : t('Yazdığımı gönder 🤲', 'Send what I wrote 🤲')),
        ),
      ],
    );
  }
}
