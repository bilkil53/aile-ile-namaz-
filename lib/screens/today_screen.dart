import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data.dart';
import '../models.dart';
import '../theme.dart';

/// "Bugün" sekmesi: karşılama, aile özeti kartı ve vakit kartları.
/// Vakte dokundukça Kıldı → Kılmadı → Muaf → Bekliyor sırasıyla ilerler.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Map<String, PrayerStatus> _mine = {};
  List<Pool> _pools = [];
  String _name = '';
  bool _loading = true;

  static const _icons = {
    'fajr': Icons.wb_twilight,
    'dhuhr': Icons.wb_sunny,
    'asr': Icons.wb_cloudy,
    'maghrib': Icons.nightlight_round,
    'isha': Icons.bedtime,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        Repo.myPools(),
        Repo.dayPrayers([myId], todayStr()),
        supa.from('profiles').select('display_name').eq('id', myId).maybeSingle(),
      ]);
      if (!mounted) return;
      final profile = results[2] as Map<String, dynamic>?;
      setState(() {
        _pools = results[0] as List<Pool>;
        _mine = (results[1] as Map<String, Map<String, PrayerStatus>>)[myId] ?? {};
        _name = (profile?['display_name'] as String? ?? '').trim();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  PrayerStatus _next(PrayerStatus s) => switch (s) {
        PrayerStatus.none => PrayerStatus.prayed,
        PrayerStatus.prayed => PrayerStatus.missed,
        PrayerStatus.missed => PrayerStatus.excused,
        PrayerStatus.excused => PrayerStatus.none,
      };

  Future<void> _toggle(String key) async {
    final next = _next(_mine[key] ?? PrayerStatus.none);
    final before = Map<String, PrayerStatus>.from(_mine);
    setState(() => _mine = {..._mine, key: next});
    try {
      await Repo.setPrayer(
        key: key,
        status: next,
        poolIds: _pools.map((p) => p.id).toList(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _mine = before);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi. İnternet bağlantını kontrol et.')),
      );
    }
  }

  int get _prayedCount =>
      prayerKeys.where((k) => _mine[k] == PrayerStatus.prayed).length;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _greeting(),
          const SizedBox(height: 14),
          _heroCard(),
          const SizedBox(height: 18),
          _trackingHeader(),
          const SizedBox(height: 12),
          for (final k in prayerKeys) ...[
            _prayerCard(k),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _greeting() {
    final date = DateFormat('d MMMM y, EEEE', 'tr').format(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AİLE İLE NAMAZ',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.emerald,
            letterSpacing: 0.8,
          ),
        ),
        Text(
          _name.isEmpty ? 'Selamün aleyküm' : 'Selamün aleyküm,\n$_name',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 2),
        Row(children: [
          const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Text(date, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ]),
      ],
    );
  }

  Widget _heroCard() {
    final hasPool = _pools.isNotEmpty;
    final white85 = Colors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.emerald,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.diversity_1, size: 14, color: Colors.white),
            SizedBox(width: 5),
            Text(
              'AİLE HAVUZU',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1),
            ),
          ]),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasPool ? _pools.first.name : 'Henüz bir havuzun yok',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      hasPool
                          ? (_pools.length > 1 ? '${_pools.length} havuza üyesin' : 'Kıldıkların ailene anında bildirilir')
                          : 'Aile Havuzu sekmesinden oluştur ya da katıl',
                      style: TextStyle(fontSize: 13, color: white85, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Text(
                '$_prayedCount/5',
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 10),
          Text(
            'Namaz, müminin miracıdır. Ailenle birlikte, vaktinde.',
            style: TextStyle(fontSize: 11, color: white85, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _trackingHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Bugünün takibi',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.emeraldContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_prayedCount/5',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.emerald),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          'Niyetinle başla; küçük bir işaret sürdürülebilirliği güçlendirir.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < prayerKeys.length; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: _mine[prayerKeys[i]] == PrayerStatus.prayed
                        ? AppColors.emerald
                        : AppColors.segmentInactive,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Vakite dokundukça Kıldı → Kılmadı → Muaf → Bekliyor sırasıyla ilerler.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _prayerCard(String key) {
    final status = _mine[key] ?? PrayerStatus.none;
    final (statusText, statusColor) = switch (status) {
      PrayerStatus.prayed => ('✓ Kılındı', AppColors.prayedMint),
      PrayerStatus.missed => ('✕ Kılınmadı', AppColors.missedCoral),
      PrayerStatus.excused => ('— Muaf', const Color(0xFFE5E7EB)),
      PrayerStatus.none => ('Dokunarak işaretle', Colors.white.withValues(alpha: 0.75)),
    };
    return Material(
      color: AppColors.emerald,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _toggle(key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icons[key], size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prayerLabels[key]!,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: status == PrayerStatus.none ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _statusCircle(status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCircle(PrayerStatus status) {
    const size = 26.0;
    return switch (status) {
      PrayerStatus.prayed => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 16, color: AppColors.emerald),
        ),
      PrayerStatus.missed => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: AppColors.missed, shape: BoxShape.circle),
          child: const Icon(Icons.close, size: 15, color: Colors.white),
        ),
      PrayerStatus.excused => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.3), shape: BoxShape.circle),
          child: const Icon(Icons.remove, size: 15, color: Colors.white),
        ),
      PrayerStatus.none => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.8),
          ),
        ),
    };
  }
}
