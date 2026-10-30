import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../content/daily_content.dart';
import '../data.dart';
import '../models.dart';
import '../theme.dart';

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
  List<(String, String, String)> _outgoing = [];
  bool _loading = true;
  bool _showYesterday = false;
  String _myName = '';
  final _joinCtrl = TextEditingController();
  String _joinRole = 'Aile Ferdi';

  RealtimeChannel? _poolChannel;
  RealtimeChannel? _meChannel;
  Stream<List<Map<String, dynamic>>>? _events;
  String? _eventsPoolId;
  Timer? _debounce;

  int _idx(int len) => (_sel >= 0 && _sel < len) ? _sel : 0;
  Pool? get _pool => _pools.isEmpty ? null : _pools[_idx(_pools.length)];
  bool get _isOwner => _pool?.ownerId == myId;

  @override
  void initState() {
    super.initState();
    _subscribeMe();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
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

  void _subscribePool(String poolId) {
    if (_eventsPoolId == poolId) return;
    if (_poolChannel != null) supa.removeChannel(_poolChannel!);
    final f = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'pool_id', value: poolId);
    _poolChannel = supa
        .channel('pool-$poolId')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'daily_prayers', callback: _refreshSoon)
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'pool_members', filter: f, callback: _refreshSoon)
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'join_requests', filter: f, callback: _refreshSoon)
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'kaza_summary', callback: _refreshSoon)
        .subscribe();
    _events = Repo.eventsStream(poolId);
    _eventsPoolId = poolId;
  }

  String _yStr() => DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));

  Future<void> _load() async {
    try {
      Repo.invalidatePools();
      final results = await Future.wait<dynamic>([Repo.myPools(), Repo.myDisplayName()]);
      final pools = results[0] as List<Pool>;
      _myName = results[1] as String;
      if (pools.isEmpty) {
        final out = await Repo.myOutgoingRequests();
        if (!mounted) return;
        setState(() {
          _pools = [];
          _outgoing = out;
          _members = [];
          _requests = [];
          _loading = false;
        });
        return;
      }
      final pool = pools[_idx(pools.length)];
      final members = await Repo.members(pool.id);
      final ids = members.map((m) => m.userId).toList();
      final r = await Future.wait<dynamic>([
        Repo.dayPrayers(ids, todayStr()),
        Repo.dayPrayers(ids, _yStr()),
        Repo.kazaSummary(ids),
        pool.ownerId == myId ? Repo.pendingRequests(pool.id) : Future.value(<JoinRequest>[]),
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
        _outgoing = [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _err(Object e) {
    final s = e.toString();
    if (s.contains('already_member')) return 'Zaten bu havuzdasın.';
    if (s.contains('too_many_attempts')) return 'Çok fazla deneme. Biraz sonra tekrar dene.';
    if (s.contains('request_expired')) return 'Bu isteğin süresi (24 saat) dolmuş.';
    if (s.contains('pool_limit_reached')) return 'En fazla 3 havuz kurabilirsin.';
    if (s.contains('owner_cannot_leave')) return 'Aile Reisi ayrılamaz; önce yöneticiliği devret.';
    return 'İşlem yapılamadı. İnternet bağlantını kontrol et.';
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

  Future<void> _startPool() async {
    try {
      final first = _myName.split(' ').first;
      await Repo.createPool('${first.isEmpty ? 'Benim' : first} Ailesi', 'Aile Reisi', '👑');
      await _load();
      _toast('Aile havuzun hazır. Kodunu ailenle paylaş.');
    } catch (e) {
      _toast(_err(e));
    }
  }

  Future<void> _join(String input, String role) async {
    final v = input.trim();
    if (v.isEmpty) return;
    try {
      final icon = familyRoles[role] ?? '👥';
      final ok = await Repo.requestJoin(v, role, icon);
      if (!ok) {
        _toast('Davet kodu geçersiz. Aile Reisinden kodu tekrar iste.');
        return;
      }
      await _load();
    } catch (e) {
      _toast(_err(e));
    }
  }

  Future<void> _approve(JoinRequest r) async {
    final ownerNow = _members.where((m) => m.userId == myId).firstOrNull;
    final res = await showDialog<(String, String, String, String)>(
      context: context,
      builder: (_) => _ApproveDialog(
        requesterName: r.name.isNotEmpty ? r.name : 'Bir aile ferdi',
        ownerRole: ownerNow?.roleTitle ?? 'Aile Reisi',
        memberRole: r.roleTitle,
      ),
    );
    if (res == null) return;
    final (ownerRole, ownerIcon, memberRole, memberIcon) = res;
    try {
      await Repo.approveWithRoles(r.id,
          memberRole: memberRole, memberIcon: memberIcon, ownerRole: ownerRole, ownerIcon: ownerIcon);
      _toast('🎉 $memberRole aile havuzuna katıldı!');
      await _load();
    } catch (e) {
      _toast(_err(e));
    }
  }

  Future<void> _sendDua({Member? to}) async {
    final text = await showDialog<String>(context: context, builder: (_) => _DuaDialog(to: to?.shownName));
    if (text == null || text.trim().isEmpty || _pool == null) return;
    final msg = to == null ? text.trim() : '${to.shownName} için: ${text.trim()}';
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
          final res = await showDialog<(String, String)>(
            context: context,
            builder: (_) => _RoleDialog(title: '${m.shownName} için unvan', initial: m.roleTitle),
          );
          if (res == null) return;
          await Repo.setMemberRole(pool.id, m.userId, res.$1, res.$2);
        case 'owner':
          if (await _confirm('Aile Reisliği ${m.shownName} kişisine devredilsin mi? Bunu geri alamazsın.') != true) return;
          await Repo.transferOwnership(pool.id, m.userId);
        case 'remove':
          if (await _confirm('${m.shownName} havuzdan çıkarılsın mı?') != true) return;
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
          _hero(),
          const SizedBox(height: 12),
          if (pool == null) ...[
            if (_outgoing.isNotEmpty) _pendingCard() else ...[
              _joinCard(),
              const SizedBox(height: 12),
              _startCard(),
            ],
          ] else ...[
            for (final r in _requests) ...[_requestCard(r), const SizedBox(height: 10)],
            _isOwner ? _codeCard(pool) : _memberStatusCard(pool),
            const SizedBox(height: 12),
            _matrix(),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.emerald,
                side: const BorderSide(color: AppColors.emerald),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            if (_isOwner)
              TextButton.icon(
                onPressed: () async {
                  if (await _confirm('Havuz kapatılırsa tüm üyeler çıkarılır ve havuz kayıtları silinir. Emin misin?',
                          yes: 'Havuzu Kapat') !=
                      true) return;
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
                ? 'Henüz bir havuza bağlı değilsin. Davet koduyla katıl ya da kendi havuzunu başlat.'
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
          const SizedBox(height: 10),
          Text('"Ailene namazı emret ve kendin de onda devamlı ol." (Tâhâ, 132)',
              style: TextStyle(fontSize: 11, color: white85, fontStyle: FontStyle.italic)),
        ],
      ),
    );
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
                child: Text('Aile Havuzuna Katıl (Davet Kodu)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.goldContainer)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('Aile Reisinin sana ilettiği davet kodunu gir:',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9))),
            const SizedBox(height: 10),
            TextField(
              controller: _joinCtrl,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Örn: ABCD-EFGH',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            Text('Ailedeki unvanın:', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9))),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in familyRoles.entries.where((e) => e.key != 'Aile Reisi'))
                ChoiceChip(
                  label: Text('${e.value} ${e.key}'),
                  selected: _joinRole == e.key,
                  onSelected: (_) => setState(() => _joinRole = e.key),
                ),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.emerald),
                onPressed: () => _join(_joinCtrl.text, _joinRole),
                child: const Text('Havuza Katıl', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
  }

  Widget _startCard() => _whiteCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('👑  Aile Reisi misin?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text(
              'Kendi aile havuzunu başlat; davet kodunu ailenle paylaş. '
              'Biri katılmak istediğinde ekranında bir onay kartı açılır ve unvanları sen belirlersin.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
              onPressed: _startPool,
              icon: const Icon(Icons.add),
              label: const Text('Aile Havuzumu Başlat'),
            ),
          ],
        ),
      );

  Widget _pendingCard() {
    final (id, poolName, ownerName) = _outgoing.first;
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
            'Onaylayıp unvanını belirlediğinde havuz burada açılacak. İstek 24 saat geçerlidir.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.35),
          ),
          const SizedBox(height: 8),
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
                  Text('"${r.roleTitle}" olarak katılmak istiyor',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ]),
              ),
            ]),
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
          Text('Aile Havuz Paylaşım Kodun (👑 Aile Reisi)',
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(pool.displayCode,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 3)),
            ),
            IconButton(
              tooltip: 'Kopyala',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(
                    text: 'Aile ile Namaz uygulamasında aile havuzumuza katıl! '
                        'Davet kodu: ${pool.displayCode}'));
                _toast('Davet mesajı kopyalandı.');
              },
              icon: const Icon(Icons.copy, color: Colors.white),
            ),
            IconButton(
              tooltip: 'Yeni kod',
              onPressed: () async {
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
            'onaylarken senin ve onun unvanını (Babası, Oğlu, Eşi…) belirlersin.',
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
              if (await _confirm('Havuzdan ayrılmak istediğine emin misin?', yes: 'Evet, Ayrıl') != true) return;
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
            toggle('Dün', _showYesterday, true),
            const SizedBox(width: 6),
            toggle('Bugün', !_showYesterday, false),
          ]),
          const SizedBox(height: 4),
          Text('ORTAK MATRİS',
              style: TextStyle(fontSize: 10, letterSpacing: 1, color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  SizedBox(
                    width: 60,
                    child: Text('VAKİT',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.7))),
                  ),
                  for (final m in _members)
                    SizedBox(
                      width: colW,
                      child: Column(children: [
                        Text(m.icon, style: const TextStyle(fontSize: 18)),
                        Text(m.userId == myId ? 'Sen' : m.shownName,
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
                        width: 60,
                        child: Text(prayerLabels[k]!,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
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
      PrayerStatus.none => ('Bekliyor', Colors.transparent, Colors.white.withValues(alpha: 0.7)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: s == PrayerStatus.none ? Border.all(color: Colors.white.withValues(alpha: 0.3)) : null,
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
                Text(isMe ? '${m.shownName} (sen)' : m.shownName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                Text(isOwner ? '• 👑 Aile Reisi' : '• 👥 Aile Ferdi',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isOwner ? AppColors.gold : AppColors.emerald)),
                if (m.name.isNotEmpty && m.name != m.shownName)
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
                  PopupMenuItem(value: 'role', child: Text('Unvan / simge değiştir')),
                  PopupMenuItem(value: 'owner', child: Text('Aile Reisi yap')),
                  PopupMenuItem(value: 'remove', child: Text('Havuzdan çıkar')),
                ],
              ),
            if (_isOwner && isMe)
              IconButton(
                tooltip: 'Unvanımı değiştir',
                onPressed: () => _memberAction(m, 'role'),
                icon: const Icon(Icons.edit, size: 18, color: AppColors.textSecondary),
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
    final who = _members.where((m) => m.userId == e.senderId).firstOrNull?.shownName ??
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
    final stream = _events;
    if (stream == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Son Hareketler',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        _whiteCard(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()));
              }
              final events = snap.data!.take(20).map(PoolEvent.fromMap).toList();
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

/// Unvan seçici: hazır şablonlar + kendin yaz.
class _RoleDialog extends StatefulWidget {
  final String title;
  final String initial;
  const _RoleDialog({required this.title, required this.initial});

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  late String _role = widget.initial;
  late final _ctrl = TextEditingController(text: familyRoles.containsKey(widget.initial) ? '' : widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: _RolePicker(
          selected: _role,
          controller: _ctrl,
          onChanged: (r) => setState(() => _role = r),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            final custom = _ctrl.text.trim();
            final role = custom.isNotEmpty ? custom : _role;
            Navigator.pop(context, (role, familyRoles[role] ?? '👥'));
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _RolePicker extends StatelessWidget {
  final String selected;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _RolePicker({required this.selected, required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in familyRoles.entries)
            ChoiceChip(
              label: Text('${e.value} ${e.key}'),
              selected: selected == e.key && controller.text.trim().isEmpty,
              onSelected: (_) {
                controller.clear();
                onChanged(e.key);
              },
            ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLength: 30,
          decoration: const InputDecoration(labelText: 'Veya kendin yaz (örn. Ahmet)'),
          onChanged: (_) => onChanged(selected),
        ),
      ],
    );
  }
}

/// Reis onayı: iki tarafın unvanı (v1.16).
class _ApproveDialog extends StatefulWidget {
  final String requesterName;
  final String ownerRole;
  final String memberRole;
  const _ApproveDialog({required this.requesterName, required this.ownerRole, required this.memberRole});

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  late String _owner = widget.ownerRole;
  late String _member = widget.memberRole;
  final _ownerCtrl = TextEditingController();
  final _memberCtrl = TextEditingController();

  @override
  void dispose() {
    _ownerCtrl.dispose();
    _memberCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('🤝 Katılım Talebini Onayla', style: TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.requesterName} havuza katılmak istiyor.',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            const Text('1. Senin ailedeki unvanın (Havuz Sahibi):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _RolePicker(selected: _owner, controller: _ownerCtrl, onChanged: (r) => setState(() => _owner = r)),
            const SizedBox(height: 12),
            const Text('2. Katılan kişinin unvanı:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _RolePicker(selected: _member, controller: _memberCtrl, onChanged: (r) => setState(() => _member = r)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: () {
            final o = _ownerCtrl.text.trim().isNotEmpty ? _ownerCtrl.text.trim() : _owner;
            final m = _memberCtrl.text.trim().isNotEmpty ? _memberCtrl.text.trim() : _member;
            Navigator.pop(context, (o, familyRoles[o] ?? '👑', m, familyRoles[m] ?? '👥'));
          },
          child: const Text('Onayla & Havuza Ekle'),
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
              controller: _ctrl,
              maxLength: 240,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Veya kendi duanı yaz',
                hintText: 'Örn: Allah kabul etsin, hayırlı ve bereketli olsun…',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('Gönder 🤲')),
      ],
    );
  }
}
