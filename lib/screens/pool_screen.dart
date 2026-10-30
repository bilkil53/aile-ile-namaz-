import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data.dart';
import '../models.dart';

class PoolScreen extends StatefulWidget {
  final Pool pool;
  const PoolScreen({super.key, required this.pool});

  @override
  State<PoolScreen> createState() => _PoolScreenState();
}

class _PoolScreenState extends State<PoolScreen> {
  late Pool _pool = widget.pool;
  List<Member> _members = [];
  List<JoinRequest> _requests = [];
  Map<String, Map<String, PrayerStatus>> _today = {};
  Map<String, List<int>> _kaza = {};
  bool _loading = true;
  RealtimeChannel? _channel;
  Timer? _debounce;
  late final Stream<List<Map<String, dynamic>>> _events =
      Repo.eventsStream(widget.pool.id);

  bool get _isOwner => _pool.ownerId == myId;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final c = _channel;
    if (c != null) supa.removeChannel(c);
    super.dispose();
  }

  /// Canlı değişiklikleri dinler: biri namaz kılınca / katılma isteği gelince ekran tazelenir.
  void _subscribe() {
    void refresh(PostgresChangePayload _) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), _load);
    }

    PostgresChangeFilter poolFilter() => PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'pool_id',
          value: _pool.id,
        );

    _channel = supa
        .channel('pool-${_pool.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'daily_prayers',
          callback: refresh,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pool_members',
          filter: poolFilter(),
          callback: refresh,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'join_requests',
          filter: poolFilter(),
          callback: refresh,
        )
        .subscribe();
  }

  Future<void> _load() async {
    try {
      final members = await Repo.members(_pool.id);
      final ids = members.map((m) => m.userId).toList();
      final results = await Future.wait([
        Repo.dayPrayers(ids, todayStr()),
        Repo.kazaSummary(ids),
        if (_isOwner) Repo.pendingRequests(_pool.id) else Future.value(<JoinRequest>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _members = members;
        _today = results[0] as Map<String, Map<String, PrayerStatus>>;
        _kaza = results[1] as Map<String, List<int>>;
        _requests = results[2] as List<JoinRequest>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Member? _member(String userId) {
    for (final m in _members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  Future<void> _leave() async {
    final ok = await _confirm('Havuzdan ayrılmak istediğinize emin misiniz?');
    if (ok != true) return;
    try {
      await Repo.leavePool(_pool.id);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _toast('Ayrılınamadı.');
    }
  }

  Future<bool?> _confirm(String text) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tabs = <Tab>[
      const Tab(text: 'Bugün'),
      const Tab(text: 'Aile'),
      const Tab(text: 'Akış'),
      if (_isOwner) Tab(text: _requests.isEmpty ? 'Yönetim' : 'Yönetim (${_requests.length})'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_pool.name),
          bottom: TabBar(
            tabs: tabs,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            dividerColor: Colors.transparent,
          ),
          actions: [
            if (!_isOwner)
              PopupMenuButton<String>(
                onSelected: (_) => _leave(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'leave', child: Text('Havuzdan ayrıl')),
                ],
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _todayTab(),
                  _familyTab(),
                  _feedTab(),
                  if (_isOwner) _adminTab(),
                ],
              ),
      ),
    );
  }

  // ---------------- Bugün ----------------
  Widget _todayTab() {
    final mine = _today[myId] ?? {};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          DateFormat('d MMMM y, EEEE', 'tr').format(DateTime.now()),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final k in prayerKeys)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(prayerLabels[k]!, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<PrayerStatus>(
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    segments: const [
                      ButtonSegment(value: PrayerStatus.prayed, label: Text('Kıldım')),
                      ButtonSegment(value: PrayerStatus.missed, label: Text('Kılmadım')),
                      ButtonSegment(value: PrayerStatus.excused, label: Text('Muaf')),
                    ],
                    selected: {
                      if ((mine[k] ?? PrayerStatus.none) != PrayerStatus.none) mine[k]!,
                    },
                    onSelectionChanged: (s) => _setPrayer(k, s.isEmpty ? PrayerStatus.none : s.first),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _setPrayer(String key, PrayerStatus status) async {
    final before = _today[myId] ?? {};
    setState(() {
      _today = {
        ..._today,
        myId: {...before, key: status},
      };
    });
    try {
      await Repo.setPrayer(key: key, status: status);
    } catch (_) {
      _toast('Kaydedilemedi.');
      _load();
    }
  }

  // ---------------- Aile ----------------
  Widget _familyTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final m in _members)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(m.icon, style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          m.userId == myId ? '${m.shownName} (siz)' : m.shownName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (m.userId == _pool.ownerId) const Text('👑'),
                    ]),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final k in prayerKeys)
                          Column(children: [
                            Text(prayerLabels[k]!, style: Theme.of(context).textTheme.labelSmall),
                            Text(
                              (_today[m.userId]?[k] ?? PrayerStatus.none).emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ]),
                      ],
                    ),
                    if (_kaza[m.userId] != null && _kaza[m.userId]![0] > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Kaza: ${_kaza[m.userId]![0]} borç, ${_kaza[m.userId]![1]} ödendi',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------- Akış ----------------
  String _describe(PoolEvent e) {
    final who = _member(e.senderId)?.shownName ?? (e.message.isNotEmpty ? e.message : 'Bir üye');
    final prayer = prayerLabels[e.prayer?.toLowerCase()] ?? '';
    return switch (e.type) {
      'PRAYED' => '$who $prayer namazını kıldı ✅',
      'MISSED' => '$who $prayer namazını kılamadı ❌',
      'KAZA' => '$who kaza namazı kıldı 🕋',
      'DUA' => '$who: ${e.message}',
      'MEMBER_JOINED' => '$who aile havuzuna katıldı 🤝',
      'MEMBER_LEFT' => '$who aile havuzundan ayrıldı 🔴',
      _ => who,
    };
  }

  Widget _feedTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await Repo.sendDua(_pool.id, 'Allah kabul etsin 🤲');
                  } catch (_) {
                    _toast('Gönderilemedi.');
                  }
                },
                icon: const Text('🤲'),
                label: const Text('Aileye dua gönder'),
              ),
            ),
          ]),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _events,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final events = snap.data!.map(PoolEvent.fromMap).toList();
              if (events.isEmpty) {
                return const Center(child: Text('Henüz bir hareket yok.'));
              }
              return ListView.separated(
                itemCount: events.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  title: Text(_describe(events[i])),
                  subtitle: Text(DateFormat('d MMM HH:mm', 'tr').format(events[i].createdAt)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------- Yönetim (sadece yönetici) ----------------
  Widget _adminTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Davet kodu'),
                const SizedBox(height: 4),
                Text(_pool.displayCode,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 2)),
                const SizedBox(height: 8),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _pool.displayCode));
                      _toast('Kod kopyalandı.');
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Kopyala'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await _confirm('Eski kod geçersiz olacak. Yeni kod üretilsin mi?');
                      if (ok != true) return;
                      try {
                        final code = await Repo.regenerateCode(_pool.id);
                        if (!mounted) return;
                        setState(() => _pool = Pool(
                              id: _pool.id,
                              name: _pool.name,
                              ownerId: _pool.ownerId,
                              inviteCode: code,
                            ));
                      } catch (_) {
                        _toast('Kod yenilenemedi.');
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Yenile'),
                  ),
                ]),
                const SizedBox(height: 4),
                const Text(
                  'Kodla katılmak isteyenler sizin onayınızı bekler.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Bekleyen istekler', style: Theme.of(context).textTheme.titleMedium),
        if (_requests.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('Bekleyen istek yok.')),
        for (final r in _requests)
          Card(
            child: ListTile(
              leading: Text(r.icon, style: const TextStyle(fontSize: 26)),
              title: Text('${r.roleTitle}${r.name.isNotEmpty ? ' • ${r.name}' : ''}'),
              subtitle: Text(r.email),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Reddet',
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () async {
                    try {
                      await Repo.reject(r.id);
                      _load();
                    } catch (_) {
                      _toast('İşlem yapılamadı.');
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Onayla',
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () async {
                    try {
                      await Repo.approve(r.id);
                      _load();
                    } catch (_) {
                      _toast('İşlem yapılamadı.');
                    }
                  },
                ),
              ]),
            ),
          ),
        const SizedBox(height: 16),
        Text('Üyeler', style: Theme.of(context).textTheme.titleMedium),
        for (final m in _members.where((m) => m.userId != myId))
          Card(
            child: ListTile(
              leading: Text(m.icon, style: const TextStyle(fontSize: 26)),
              title: Text(m.shownName),
              subtitle: Text(m.name),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  final ok = await _confirm(v == 'remove'
                      ? '${m.shownName} havuzdan çıkarılsın mı?'
                      : 'Yöneticilik ${m.shownName} kişisine devredilsin mi? Bunu geri alamazsınız.');
                  if (ok != true) return;
                  try {
                    if (v == 'remove') {
                      await Repo.removeMember(_pool.id, m.userId);
                      _load();
                    } else {
                      await Repo.transferOwnership(_pool.id, m.userId);
                      if (!mounted) return;
                      Navigator.of(context).pop();
                    }
                  } catch (_) {
                    _toast('İşlem yapılamadı.');
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'transfer', child: Text('Yönetici yap')),
                  PopupMenuItem(value: 'remove', child: Text('Havuzdan çıkar')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
