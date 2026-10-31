import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../content/daily_content.dart';
import '../data.dart';
import '../local_store.dart';
import '../models.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets/prayer_icon.dart';

/// Aile Havuzu • İbadet Halkası (eski uygulama v1.14–v1.18 akışı).
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
  Stream<List<Map<String, dynamic>>>? _events;
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
    _events = Repo.eventsStream(poolId);
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
      final members = await Repo.members(pool.id);
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

  // ---------- Gezinti (misafir) modu: her şey bellekte, uygulama kapanınca silinir ----------
  final List<PoolEvent> _guestFeed = [];

  Future<void> _loadGuest() async {
    final me = Member(userId: myId, name: 'Misafir', roleTitle: 'Aile Ferdi', icon: '👤');
    final pool = Pool(id: 'local', name: 'Aile İbadet Havuzum', ownerId: myId, inviteCode: 'EMB-······');
    final t = await Repo.dayPrayers([myId], todayStr());
    final y = await Repo.dayPrayers([myId], _yStr());
    if (!mounted) return;
    setState(() {
      _pools = [pool];
      _members = [me];
      _myName = 'Misafir';
      _today = t;
      _yesterday = y;
      _loading = false;
    });
  }

  /// Bulut gerektiren işlemlerde giriş penceresi.
  Future<void> _needLogin(String what) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Text('🔐', style: TextStyle(fontSize: 34)),
        title: const Text('Google Girişi Gerekir', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        content: Text(
          '$what için Google ile giriş yapmalısın.\n\n'
          'Şu an gezinti modundasın: yaptığın işaretlemeler sadece bu oturumda tutulur ve uygulama kapanınca silinir. '
          'Giriş yaparsan bu oturumdakiler buluta kaydedilir.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Gezinmeye Devam')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Google ile Giriş Yap'),
          ),
        ],
      ),
    );
    if (go == true) await LocalStore.setGuestMode(false);
  }

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
    if (isGuest) return _needLogin('Aile bağlantısını sorgulamak');
    setState(() => _checkingLink = true);
    final before = _members.length;
    await _load();
    if (!mounted) return;
    setState(() => _checkingLink = false);
    if (_members.length > 1) {
      _toast(_members.length > before
          ? '🎉 Bağlantı kuruldu! Aile havuzunda ${_members.length} kişisiniz.'
          : '🟢 Bağlantı aktif: ${_members.length} kişi aile havuzunda.');
    } else if (_outgoing.isNotEmpty) {
      _toast('⏳ Talebin hâlâ Aile Reisinin onayını bekliyor (${_mmss(_left(_outgoing.first.$4))} kaldı).');
    } else if (_requests.isNotEmpty) {
      _toast('🔔 Onay bekleyen ${_requests.length} katılım isteğin var.');
    } else {
      _toast('Henüz bağlı bir aile ferdi yok. Davet kodunu paylaş veya bir koda katıl.');
    }
  }

  String _err(Object e) {
    final s = e.toString();
    if (s.contains('already_member')) return 'Zaten bu havuzdasın.';
    if (s.contains('too_many_attempts')) return 'Çok fazla deneme. Biraz sonra tekrar dene.';
    if (s.contains('request_expired')) return 'İsteğin 5 dakikalık onay süresi doldu. Tekrar istek gönderebilirsin.';
    if (s.contains('rate_limited')) return 'Çok sık gönderdin. Biraz bekleyip tekrar dene.';
    if (s.contains('pending_exists')) return 'Zaten bekleyen bir katılım isteğin var. 5 dakika içinde onaylanmazsa yenisini gönderebilirsin.';
    if (s.contains('invalid_owner_role')) return 'Kendi ünvanın Aile Reisi, Baba veya Anne olabilir.';
    if (s.contains('pool_limit_reached')) return 'En fazla 3 havuz kurabilirsin.';
    if (s.contains('owner_cannot_leave')) return 'Aile Reisi ayrılamaz; önce yöneticiliği devret.';
    return 'İşlem yapılamadı. İnternet bağlantını kontrol et.';
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
          title: Text(title, style: const TextStyle(fontSize: 18)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: a,
              onChanged: (v) => setD(() => a = v ?? false),
              title: Text('1. onay: $first', style: const TextStyle(fontSize: 13)),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: b,
              onChanged: a ? (v) => setD(() => b = v ?? false) : null,
              title: Text('2. onay: $second', style: const TextStyle(fontSize: 13)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
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

  Future<bool?> _confirm(String text, {String yes = 'Evet'}) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
          ],
        ),
      );

  // ======================= Eylemler =======================

  Future<void> _join(String input) async {
    final v = input.trim();
    if (v.isEmpty) return;
    if (isGuest) return _needLogin('Bir aile havuzuna katılmak');
    try {
      // Unvanı ve simgeyi onaylarken Aile Reisi belirler.
      final ok = await Repo.requestJoin(v, 'Aile Ferdi', '👥');
      if (!ok) {
        _toast('Davet kodu geçersiz. Aile Reisinden kodu tekrar iste.');
        return;
      }
      await _load();
    } catch (e) {
      // İnternet kesilmiş olabilir: istek sunucuya ulaştı mı kontrol et.
      // Ulaşmadıysa tekrar denenebilir; ulaştıysa 5 dk içinde onaylanmazsa kendiliğinden düşer.
      await _load();
      if (!mounted) return;
      if (_outgoing.isNotEmpty) {
        _toast('Talebin iletildi ⏳ Aile Reisinin onayı bekleniyor.');
      } else if (e.toString().contains('pending_exists') || e.toString().contains('rate_limited') ||
          e.toString().contains('already_member') || e.toString().contains('too_many_attempts')) {
        _toast(_err(e));
      } else {
        _toast('Talep iletilemedi. İnternet bağlantını kontrol edip tekrar dene.');
      }
    }
  }

  Future<void> _approve(JoinRequest r) async {
    final who = r.name.isNotEmpty ? r.name : 'Bir aile ferdi';
    final me = _members.where((m) => m.userId == myId).firstOrNull;
    final res = await showDialog<_TitleResult>(
      context: context,
      builder: (_) => _TitleDialog(
        initialOwnerGender: me?.gender,
        title: '🤝 $who havuzuna katılmak istiyor',
        subtitle: 'Sana göre unvanını ve simgesini seç:',
        initialTitle: 'Aile Ferdi',
        initialIcon: '👥',
        confirm: 'Onayla & Havuza Ekle',
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
      _toast('🎉 ${res.title} aile havuzuna katıldı!');
      await _load();
    } catch (e) {
      _toast(_err(e));
    }
  }

  String get _myRole => _members.where((m) => m.userId == myId).firstOrNull?.roleTitle ?? 'Aile Ferdi';

  Future<void> _sendDua({Member? to}) async {
    final text = await showDialog<String>(context: context, builder: (_) => _DuaDialog(to: to == null ? null : _label(to)));
    if (text == null || text.trim().isEmpty || _pool == null) return;
    final msg = to == null ? text.trim() : '${to.shownName} için: ${text.trim()}';
    if (isGuest) {
      setState(() => _guestFeed.insert(
          0,
          PoolEvent(
              id: _guestFeed.length,
              senderId: myId,
              type: 'DUA',
              prayer: null,
              message: msg,
              createdAt: DateTime.now())));
      _toast('Dua bu oturumda kaydedildi 🤲 Ailene gitmesi için giriş yap.');
      return;
    }
    try {
      await Repo.sendDua(_pool!.id, msg.length > 280 ? msg.substring(0, 280) : msg);
      _toast('Dua gönderildi 🤲');
    } catch (e) {
      _toast(_err(e));
    }
  }

  Future<void> _memberAction(Member m, String action) async {
    final pool = _pool;
    if (pool == null) return;
    try {
      switch (action) {
        case 'role':
          final res = await showDialog<_TitleResult>(
            context: context,
            builder: (_) => _TitleDialog(
              title: m.name.isNotEmpty ? m.name : _label(m),
              subtitle: 'Sana göre unvanı ve simgesi:',
              initialTitle: m.roleTitle,
              initialIcon: m.icon,
              initialGender: m.gender,
              confirm: 'Kaydet',
            ),
          );
          if (res == null) return;
          await Repo.setMemberRole(pool.id, m.userId, res.title, res.icon, gender: res.gender);
        case 'owner':
          if (await _confirm('Aile Reisliği ${_label(m)} kişisine devredilsin mi? Bunu geri alamazsın.') != true) return;
          await Repo.transferOwnership(pool.id, m.userId);
        case 'remove':
          if (await _confirm('${_label(m)} havuzdan çıkarılsın mı?') != true) return;
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
              child: const Row(children: [
                Icon(Icons.wifi_off, color: Color(0xFF78350F), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('İnternet yok: ailenin son bilinen durumu gösteriliyor. Bağlantı gelince kendiliğinden yenilenir.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF78350F))),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],
          _profileCard(),
          const SizedBox(height: 12),
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
              label: const Text('Aileye Dua Gönder', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            _membersSection(),
            const SizedBox(height: 16),
            _feed(),
            const SizedBox(height: 16),
            if (_isOwner && _members.length > 1)
              TextButton.icon(
                onPressed: () async {
                  if (!await _doubleConfirm(
                    title: 'Havuzu Kapat & Sıfırla',
                    text: 'Havuz kapatılırsa bütün aile fertleri havuzdan çıkarılır; ünvanlar, dua ve hareket kayıtları silinir. '
                        'Herkesin kendi namaz ve kaza kayıtları kendi hesabında kalır.',
                    first: 'Tüm üyelerin havuzdan çıkarılacağını anladım',
                    second: 'Havuzu kapatmak istiyorum',
                    yes: 'Havuzu Kapat',
                  )) return;
                  try {
                    await Repo.deletePool(pool.id);
                    _sel = 0;
                    await _load();
                  } catch (e) {
                    _toast(_err(e));
                  }
                },
                icon: const Icon(Icons.delete_forever, color: AppColors.missed),
                label: const Text('Havuzu Kapat & Sıfırla', style: TextStyle(color: AppColors.missed)),
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
          const Row(children: [
            Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 14)),
            SizedBox(width: 6),
            Text('AİLE HAVUZU • İBADET HALKASI',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
          ]),
          const SizedBox(height: 10),
          Text(pool?.name ?? 'Aile İbadet Havuzu',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          Text(
            pool == null
                ? 'Aile havuzun hazırlanıyor…'
                : _members.length <= 1
                    ? 'Davet kodunu ailenle paylaş; katıldıkça burada görünecekler.'
                    : '${_members.length} kişi • Aile Havuzunda Bağlı 🟢 Aktif',
            style: TextStyle(fontSize: 13, color: white85),
          ),
          if (_pools.length > 1) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (var i = 0; i < _pools.length; i++)
                ChoiceChip(
                  label: Text(_pools[i].name),
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
              child: Text(_members.length > 1 ? '🟢 AKTİF' : '⏳ BEKLEMEDE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _members.length > 1 ? AppColors.emeraldDark : const Color(0xFF78350F))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_members.length > 1 ? 'Bağlantı Kuruldu ✓' : 'Bağlantı Bekleniyor ⏳',
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
              label: Text(_checkingLink ? 'Sorgulanıyor…' : 'Bağlantıyı Teyit Et',
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

  Widget _guestBanner() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.goldContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Text('👀', style: TextStyle(fontSize: 20)),
            SizedBox(width: 8),
            Expanded(
              child: Text('Gezinti Modu',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF78350F))),
            ),
          ]),
          const SizedBox(height: 4),
          const Text(
            'Aile Havuzunu deneyebilirsin; yaptıkların sadece bu oturumda tutulur ve uygulama kapanınca silinir. '
            'Ailenle gerçekten bağlanmak ve kayıtlarını buluta almak için giriş yap.',
            style: TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.35),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
            onPressed: () => LocalStore.setGuestMode(false),
            icon: const Icon(Icons.login, size: 18),
            label: const Text('Google ile Giriş Yap & Buluta Kaydet', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
      );

  Widget _profileCard() {
    final family = _members.length > 1;
    final me = _members.where((m) => m.userId == myId).firstOrNull;
    return _whiteCard(
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.emeraldContainer,
          child: Text(me?.icon ?? '👤', style: const TextStyle(fontSize: 24)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_myName.isNotEmpty ? _myName : 'Aile Ferdi',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            Text('${me?.roleTitle ?? 'Aile Ferdi'} · ${isGuest ? 'Gezinti modu (giriş yapılmadı)' : 'Google Hesabı Bağlı ✓'}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: family ? AppColors.emerald : AppColors.emeraldContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(family ? 'Aile Modu' : 'Bireysel Mod',
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
      Text('Onay için kalan süre: ${_mmss(left)}',
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
            const Row(children: [
              Text('📥', style: TextStyle(fontSize: 16)),
              SizedBox(width: 6),
              Expanded(
                child: Text('Başka Bir Aile Havuzuna Katıl',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.goldContainer)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('Aile Reisin sen değilsen, onun sana ilettiği davet kodunu gir:',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9))),
            const SizedBox(height: 10),
            TextField(
              controller: _joinCtrl,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Örn: EMB-123456',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            Text('Katıldıktan sonra ünvanını (Eşi, Oğlu, Kızı…) ve simgeni Aile Reisi belirler.',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.emerald),
                onPressed: () => _join(_joinCtrl.text),
                child: const Text('Havuza Katıl', style: TextStyle(fontWeight: FontWeight.bold)),
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
          const Row(children: [
            Text('⏳', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('Katılım Talebi İletildi',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF78350F))),
          ]),
          const SizedBox(height: 6),
          Text(
            '"$poolName" havuzuna katılma isteğin ${ownerName.isNotEmpty ? '$ownerName adlı ' : ''}Aile Reisine iletildi. '
            'Onaylayıp ünvanını belirlediğinde havuz burada açılacak. '
            'Talep 5 dakika içinde onaylanmalıdır; bu sürede başka talep gönderemezsin.',
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
            child: const Text('Talebi İptal Et'),
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
            const Row(children: [
              Text('🔔', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Expanded(
                child: Text('Aşağıdaki aile ferdin havuzuna dahil olmak istiyor:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF78350F))),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Text(r.icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name.isNotEmpty ? r.name : 'Bir aile ferdi',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const Text('Onaylarken ünvanını ve simgesini sen belirleyeceksin.',
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
                  child: const Text('Onayla & Rol Seç'),
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
                child: const Text('Reddet'),
              ),
            ]),
          ],
        ),
      );

  Widget _codeCard(Pool pool) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.emeraldLight, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Davet Kodunuzu Paylaşın 🔗',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          Text('Aile Havuz Paylaşım Kodun',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(pool.displayCode,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 3)),
            ),
            IconButton(
              tooltip: 'Paylaş',
              onPressed: () async {
                if (isGuest) return _needLogin('Davet kodu oluşturmak');
                await Share.share(
                  '🕌 Aile ile Namaz uygulamasında aile havuzumuza katıl!\n\n'
                  'Davet kodu: ${pool.displayCode}\n'
                  '(Kodu 5 dakika içinde onaylarım.)\n\n'
                  'Uygulama: https://github.com/bilkil53/aile-ile-namaz-/releases/latest/download/aile-ile-namaz.apk',
                  subject: 'Aile Havuzu davet kodu',
                );
              },
              icon: const Icon(Icons.share, color: Colors.white),
            ),
            IconButton(
              tooltip: 'Kopyala',
              onPressed: () async {
                if (isGuest) return _needLogin('Davet kodu oluşturmak');
                await Clipboard.setData(ClipboardData(text: pool.displayCode));
                _toast('Kod kopyalandı: ${pool.displayCode}');
              },
              icon: const Icon(Icons.copy, color: Colors.white),
            ),
            IconButton(
              tooltip: 'Yeni kod',
              onPressed: () async {
                if (isGuest) return _needLogin('Davet kodu oluşturmak');
                if (await _confirm('Eski kod geçersiz olacak. Yeni kod üretilsin mi?') != true) return;
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
            'Bu kodu ailenle paylaş. Katılmak istediklerinde burada onay kartı açılır; '
            'onaylarken ona sana göre ünvanını (Eşi, Oğlu, Kızı…) ve simgesini verirsin.',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85), height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _memberStatusCard(Pool pool) => _whiteCard(
        child: Row(children: [
          const Text('🕌', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Aile İbadet Havuzundasın',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ),
          TextButton(
            onPressed: () async {
              if (!await _doubleConfirm(
                title: 'Havuzdan Ayrıl',
                text: 'Ayrılırsan ailen senin namaz durumunu artık göremez, sen de onlarınkini göremezsin. '
                    'Kendi namaz ve kaza kayıtların hesabında kalır. Tekrar katılmak için Aile Reisinden yeni onay gerekir.',
                first: 'Ailemin durumunu artık göremeyeceğimi anladım',
                second: 'Havuzdan ayrılmak istiyorum',
                yes: 'Evet, Ayrıl',
              )) return;
              try {
                await Repo.leavePool(pool.id);
                _sel = 0;
                await _load();
              } catch (e) {
                _toast(_err(e));
              }
            },
            child: const Text('Havuzdan Ayrıl', style: TextStyle(color: AppColors.missed)),
          ),
        ]),
      );

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
            const Text('👨‍👩‍👧', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Aile İbadet Halkası',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            toggle('◄ Dünü Gör', _showYesterday, true),
            const SizedBox(width: 6),
            toggle('Bugün', !_showYesterday, false),
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
                const Text('🏆', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${_showYesterday ? 'Dün' : 'Bugün'} Aile Başarısı: $done / $total Vakit',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                Text('%$pct',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.prayedMint)),
              ]),
            );
          }),
          Row(children: [
            Text('ORTAK MATRİS',
                style: TextStyle(fontSize: 10, letterSpacing: 1, color: Colors.white.withValues(alpha: 0.7))),
            const Spacer(),
            if (_members.length > 3)
              Text('Sağa Kaydırılabilir (${_members.length} Kişi) →',
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
                    child: Text('VAKİT',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.7))),
                  ),
                  for (final m in _members)
                    SizedBox(
                      width: colW,
                      child: Column(children: [
                        Text(m.icon, style: const TextStyle(fontSize: 18)),
                        Text(m.userId == myId ? 'Sen' : _label(m),
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
      PrayerStatus.prayed => ('Kıldı', Colors.white, AppColors.emerald),
      PrayerStatus.missed => ('Kılmadı', AppColors.missed, Colors.white),
      PrayerStatus.excused => ('Muaf', Colors.white.withValues(alpha: 0.25), Colors.white),
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
        const Text('Havuzdaki Bireyler ve Durumları',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        for (final m in _members) ...[
          _memberCard(m, pool),
          const SizedBox(height: 8),
        ],
        if (_members.length == 1)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Aile fertlerin davet kodun ile havuza dahil oldukça burada listelenecek ⏳',
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
            Text(m.icon, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isMe ? '${m.shownName} (sen)' : _label(m),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                Text(isOwner ? '• 🏡 Havuz Yöneticisi' : '• 👥 Aile Ferdi',
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
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'role', child: Text('Ünvan / simge belirle')),
                  PopupMenuItem(value: 'owner', child: Text('Aile Reisi yap')),
                  PopupMenuItem(value: 'remove', child: Text('Havuzdan çıkar')),
                ],
              ),
          ]),
          if (kazaLeft > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.goldContainer, borderRadius: BorderRadius.circular(8)),
              child: Text('📿 Kaza: $kazaLeft kaldı • ${kaza![1]} eda edildi',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF78350F))),
            ),
          ],
          if (!isMe) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => _sendDua(to: m),
              icon: const Text('👏'),
              label: const Text('Tebrik Et & Dua Gönder',
                  style: TextStyle(color: AppColors.emerald, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- Akış ----------
  String _describe(PoolEvent e) {
    final whoM = _members.where((m) => m.userId == e.senderId).firstOrNull;
    final who = (whoM == null ? null : _label(whoM)) ??
        (e.message.isNotEmpty ? e.message : 'Bir üye');
    final prayer = prayerLabels[e.prayer?.toLowerCase()] ?? '';
    return switch (e.type) {
      'PRAYED' => '$who $prayer namazını kıldı ✅',
      'MISSED' => '$who $prayer namazını kılamadı',
      'KAZA' => '$who bir kaza namazı eda etti 📿',
      'DUA' => '$who: ${e.message}',
      'MEMBER_JOINED' => '$who aile havuzuna katıldı 🤝',
      'MEMBER_LEFT' => '$who aile havuzundan ayrıldı',
      _ => who,
    };
  }

  Widget _feed() {
    if (isGuest) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Son Hareketler (bu oturum)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        _whiteCard(
          child: _guestFeed.isEmpty
              ? const Text('Henüz bir hareket yok. Uygulama kapanınca bu liste silinir.',
                  style: TextStyle(color: AppColors.textMuted))
              : Column(children: [
                  for (final e in _guestFeed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(child: Text(_describe(e), style: const TextStyle(fontSize: 13))),
                        Text(DateFormat('HH:mm', 'tr').format(e.createdAt),
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                      ]),
                    ),
                ]),
        ),
      ]);
    }
    final stream = _events;
    if (stream == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Son Hareketler (son 5)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        _whiteCard(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()));
              }
              final events = snap.data!.take(5).map(PoolEvent.fromMap).toList();
              if (events.isEmpty) {
                return const Text('Henüz bir hareket yok.', style: TextStyle(color: AppColors.textMuted));
              }
              return Column(children: [
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Text(_describe(e), style: const TextStyle(fontSize: 13))),
                      const SizedBox(width: 8),
                      Text(DateFormat('HH:mm', 'tr').format(e.createdAt),
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ]),
                  ),
              ]);
            },
          ),
        ),
      ],
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
  late String? _gender = widget.initialGender ?? _genderOf(widget.initialTitle);
  late String? _ownerGender = widget.initialOwnerGender;

  static String? _genderOf(String title) =>
      femaleTitles.contains(title) ? 'f' : (maleTitles.contains(title) ? 'm' : null);

  Widget _genderRow(String label, String? value, ValueChanged<String> onPick) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
          for (final (code, text) in const [('m', '🧔 Erkek'), ('f', '🧕 Kadın')])
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(label: Text(text), selected: value == code, onSelected: (_) => onPick(code)),
            ),
        ]),
      );
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
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.askOwner) ...[
              const Text('Senin ünvanın', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final e in ownerTitles.entries)
                  ChoiceChip(
                    label: Text('${e.value} ${e.key}'),
                    selected: _owner == e.key,
                    onSelected: (_) => setState(() => _owner = e.key),
                  ),
              ]),
              if (_owner == 'Aile Reisi')
                _genderRow('Senin cinsiyetin', _ownerGender, (g) => setState(() => _ownerGender = g)),
              const Divider(height: 22),
            ],
            Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            const Text('Ünvanı (sana göre)', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    _gender = _genderOf(e.key) ?? _gender;
                  }),
                ),
            ]),
            TextField(
              controller: _ctrl,
              maxLength: 30,
              decoration: const InputDecoration(labelText: 'Veya ismini yaz (örn. Ahmet)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            _genderRow('Cinsiyeti (Muaf için)', _gender, (g) => setState(() => _gender = g)),
            const Text('Simgesi', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final g in iconGroups.entries) ...[
              const SizedBox(height: 6),
              Text(g.key, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
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
                      child: Text(ic, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ]),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
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
class _DuaDialog extends StatefulWidget {
  final String? to;
  const _DuaDialog({this.to});

  @override
  State<_DuaDialog> createState() => _DuaDialogState();
}

class _DuaDialogState extends State<_DuaDialog> {
  final _ctrl = TextEditingController();
  static const _defaultDua = 'Allah ibadetlerimizi kabul etsin, ailemizi namazda buluştursun 🤲';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.to == null ? '🤲 Dua ve Tebrik Gönder' : '🤲 ${widget.to} için dua',
          style: const TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hazır manevi dualar ve tebrikler:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            for (final g in greetings)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  dense: true,
                  leading: Text(g.emoji, style: const TextStyle(fontSize: 20)),
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
              decoration: const InputDecoration(
                labelText: 'Veya kendi duanı yaz',
                hintText: 'Örn: Allah kabul etsin, hayırlı ve bereketli olsun…',
              ),
            ),
            if (_ctrl.text.trim().isEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.emeraldContainer, borderRadius: BorderRadius.circular(10)),
                child: Text('Bir şey yazmazsan şu dua gönderilir:\n"$_defaultDua"',
                    style: const TextStyle(fontSize: 12, color: AppColors.emerald)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          // Boş bırakılırsa gönderilecek dua önizlemede yazar
          onPressed: () => Navigator.pop(context, _ctrl.text.trim().isEmpty ? _defaultDua : _ctrl.text),
          child: Text(_ctrl.text.trim().isEmpty ? 'Hazır duayı gönder 🤲' : 'Yazdığımı gönder 🤲'),
        ),
      ],
    );
  }
}
