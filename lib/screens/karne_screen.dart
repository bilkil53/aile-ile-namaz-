import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data.dart';
import '../models.dart';
import '../theme.dart';

/// İbadet karnesi: son 7 gün tablosu, haftalık/aylık oran, seri.
class KarneScreen extends StatefulWidget {
  const KarneScreen({super.key});

  @override
  State<KarneScreen> createState() => _KarneScreenState();
}

class _KarneScreenState extends State<KarneScreen> {
  Map<String, Map<String, PrayerStatus>> _data = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    try {
      // Tek sorguda son 30 gün
      final d = await Repo.myRange(now.subtract(const Duration(days: 29)), now);
      if (mounted) setState(() => _data = d);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Karne yüklenemedi.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _k(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  int _prayedOn(DateTime d) =>
      prayerKeys.where((k) => _data[_k(d)]?[k] == PrayerStatus.prayed).length;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final today = DateTime.now();
    final days7 = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
    final week = days7.fold<int>(0, (a, d) => a + _prayedOn(d));
    var month = 0;
    for (var i = 0; i < 30; i++) {
      month += _prayedOn(today.subtract(Duration(days: i)));
    }
    // Seri: bugünden geriye 5/5 kılınan ardışık gün (bugün tamamlanmadıysa dünden başla)
    var streak = 0;
    var start = _prayedOn(today) == 5 ? 0 : 1;
    for (var i = start; i < 30; i++) {
      if (_prayedOn(today.subtract(Duration(days: i))) == 5) {
        streak++;
      } else {
        break;
      }
    }
    final weekPct = (week / 35 * 100).round();
    final monthPct = (month / 150 * 100).round();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.emerald, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.emoji_events, size: 14, color: Colors.white),
                  SizedBox(width: 5),
                  Text('İBADET KARNESİ',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
                ]),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _stat('$week/35', 'Bu hafta'),
                    _stat('%$monthPct', 'Son 30 gün'),
                    _stat('$streak gün', 'Tam gün serisi'),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: week / 35,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    color: AppColors.prayedMint,
                  ),
                ),
                const SizedBox(height: 6),
                Text('Haftalık hedefin %$weekPct tamamlandı.',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Son 7 gün',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              children: [
                Row(children: [
                  const SizedBox(width: 72),
                  for (final k in prayerKeys)
                    Expanded(
                      child: Text(prayerLabels[k]!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ),
                ]),
                const SizedBox(height: 6),
                for (final d in days7.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          _k(d) == _k(today) ? 'Bugün' : DateFormat('d MMM EEE', 'tr').format(d),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                      ),
                      for (final k in prayerKeys)
                        Expanded(child: Center(child: _dot(_data[_k(d)]?[k] ?? PrayerStatus.none))),
                    ]),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text('✓ kılındı   ✕ kılınmadı   — muaf   ○ işaretlenmedi',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
          ],
        ),
      );

  Widget _dot(PrayerStatus s) {
    const size = 22.0;
    return switch (s) {
      PrayerStatus.prayed => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: AppColors.emerald, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 14, color: Colors.white),
        ),
      PrayerStatus.missed => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: AppColors.missed, shape: BoxShape.circle),
          child: const Icon(Icons.close, size: 13, color: Colors.white),
        ),
      PrayerStatus.excused => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(color: Color(0xFF9CA3AF), shape: BoxShape.circle),
          child: const Icon(Icons.remove, size: 13, color: Colors.white),
        ),
      PrayerStatus.none => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.segmentInactive, width: 2),
          ),
        ),
    };
  }
}
