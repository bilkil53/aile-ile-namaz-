import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:package_info_plus/package_info_plus.dart';

import '../content/daily_content.dart';
import '../data.dart';
import '../models.dart';
import '../settings.dart';
import '../theme.dart';

/// İbadet Karnesi (eski uygulamadaki düzen): haftalık başarı, 7 günlük grafik,
/// günün vakit detayı, gerçek veriyle hesaplanan rozetler ve Birlikte Secde.
class KarneScreen extends StatefulWidget {
  const KarneScreen({super.key});

  @override
  State<KarneScreen> createState() => _KarneScreenState();
}

class _KarneScreenState extends State<KarneScreen> {
  Map<String, Map<String, PrayerStatus>> _data = {};
  Map<String, Map<String, Map<String, PrayerStatus>>> _family = {};
  List<String> _familyIds = [];
  int _kazaDone = 0;
  String _name = '';
  String _version = '';
  bool _loading = true;
  late DateTime _selected = DateTime.now();

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    });
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 29));
    try {
      final r = await Future.wait<dynamic>([
        Repo.myRange(from, now),
        Repo.myKaza(),
        Repo.myDisplayName(),
      ]);
      final kaza = r[1] as Map<String, (int, int)>;
      if (!mounted) return;
      setState(() {
        _data = r[0] as Map<String, Map<String, PrayerStatus>>;
        _kazaDone = kaza.values.fold(0, (a, v) => a + v.$2);
        _name = r[2] as String;
      });
      if (!isGuest) {
        final pools = await Repo.myPools();
        if (pools.isNotEmpty) {
          final members = await Repo.members(pools.first.id);
          final ids = members.map((m) => m.userId).where((id) => id != myId).toList();
          final fam = ids.isEmpty ? <String, Map<String, Map<String, PrayerStatus>>>{} : await Repo.rangeFor(ids, from, now);
          if (mounted) {
            setState(() {
              _familyIds = ids;
              _family = fam;
            });
          }
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Karne yüklenemedi.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _k(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  int _prayedOn(DateTime d) => prayerKeys.where((k) => _data[_k(d)]?[k] == PrayerStatus.prayed).length;

  /// Ailemden en az biriyle aynı vakti kıldığım sayı (son 7 gün).
  int _together(List<DateTime> days) {
    var n = 0;
    for (final d in days) {
      final key = _k(d);
      for (final p in prayerKeys) {
        if (_data[key]?[p] != PrayerStatus.prayed) continue;
        final fam = _family[key] ?? {};
        if (_familyIds.any((id) => fam[id]?[p] == PrayerStatus.prayed)) n++;
      }
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final today = DateTime.now();
    final days7 = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
    final week = days7.fold<int>(0, (a, d) => a + _prayedOn(d));
    final weekPct = (week / 35 * 100).round();
    final together = _together(days7);
    final hasFamily = _familyIds.isNotEmpty;

    // Rozetler (son 7 gün)
    final fajr7 = days7.where((d) => _data[_k(d)]?['fajr'] == PrayerStatus.prayed).length;
    final fullDays = days7.where((d) => _prayedOn(d) == 5).length;
    final badges = [
      ('🌅', 'Sabah Namazı Muhafızı', 'Son 7 günün en az 5\'inde sabah namazını kıl', fajr7 >= 5, '$fajr7/5'),
      ('🏆', '5\'te 5 Sadakati', 'Bir günün 5 vaktini de eksiksiz kıl', fullDays >= 1, '$fullDays gün'),
      ('📿', 'Kaza Avcısı', 'En az 10 kaza namazı eda et', _kazaDone >= 10, '$_kazaDone/10'),
      ('🤝', 'İbadet Kardeşliği', 'Ailenle aynı vakitte 10 kez secde et', together >= 10, '$together/10'),
      ('⭐', 'İstikrar Yıldızı', 'Haftalık başarı oranını %80 ve üzerine çıkar', weekPct >= 80, '%$weekPct'),
    ];
    final sel = _data[_k(_selected)] ?? {};
    final hadis = dailyQuotes().firstWhere((q) => q.category.contains('Hadis'), orElse: () => dailyQuotes().first);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ---------- Başlık + haftalık başarı ----------
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.emerald, borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${_name.isNotEmpty ? _name : 'Aile Ferdi'} · Karnesi',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Haftalık Namaz Başarısı',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('%$weekPct',
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Text('Başarı Oranı',
                      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.85))),
                ),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: week / 35,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  color: AppColors.prayedMint,
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                _stat('$week/35', 'Kılınan Vakit'),
                _stat('$_kazaDone', 'Eda Edilen Kaza'),
                _stat(hasFamily ? 'Aile' : 'Tekil', 'Aile Uyumu'),
              ]),
            ]),
          ),
          const SizedBox(height: 14),

          // ---------- 7 günlük grafik ----------
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📊 Son 7 Gün', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Text('Bir güne dokun, vakit detayını gör',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final d in days7)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selected = d),
                      behavior: HitTestBehavior.opaque,
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text('${_prayedOn(d)}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                        const SizedBox(height: 3),
                        Container(
                          width: 22,
                          height: 8 + 72 * _prayedOn(d) / 5,
                          decoration: BoxDecoration(
                            color: _k(d) == _k(_selected)
                                ? AppColors.gold
                                : (_prayedOn(d) == 5 ? AppColors.emerald : AppColors.emeraldLight.withValues(alpha: 0.6)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(_k(d) == _k(today) ? 'Bugün' : DateFormat('EEE', 'tr').format(d),
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: _k(d) == _k(_selected) ? FontWeight.bold : FontWeight.normal,
                                color: AppColors.textPrimary)),
                        Text(DateFormat('d MMM', 'tr').format(d),
                            style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ])),
          const SizedBox(height: 14),

          // ---------- Seçili günün vakit detayı ----------
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _k(_selected) == _k(today)
                  ? '🕌 Bugünün Vakit Detayı'
                  : '🕌 ${DateFormat('d MMMM EEEE', 'tr').format(_selected)} Vakit Detayı',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final k in prayerKeys)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Text(prayerEmoji[k]!, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${prayerLabels[k]} Namazı',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      Text(prayerSubtitles[k]!, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ]),
                  ),
                  _status(sel[k] ?? PrayerStatus.none),
                ]),
              ),
          ])),
          const SizedBox(height: 14),

          // ---------- Birlikte Secde ----------
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.emeraldLight, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Text('🤲', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Birlikte Secde',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text(
                    hasFamily
                        ? 'Bu hafta ailenle aynı vakitte $together kez secde ettin.'
                        : 'Aile havuzuna biri katıldığında ortak vakitleriniz burada sayılır.',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ]),
              ),
              if (hasFamily)
                Text('$together',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.prayedMint)),
            ]),
          ),
          const SizedBox(height: 14),

          // ---------- Rozetler ----------
          const Text('🏅 Manevi Rozetler',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          for (final (emoji, title, desc, earned, progress) in badges)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: earned ? AppColors.goldContainer : AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: earned ? AppColors.gold : AppColors.cardBorder),
              ),
              child: Row(children: [
                Opacity(opacity: earned ? 1 : 0.35, child: Text(emoji, style: const TextStyle(fontSize: 28))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text(desc, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(earned ? 'Kazanıldı ✓' : 'Kilitli 🔒',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: earned ? const Color(0xFF78350F) : AppColors.textMuted)),
                  Text(progress, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ]),
              ]),
            ),
          const SizedBox(height: 6),

          // ---------- Günün Hadisi ----------
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('📖 Günün Hadis-i Şerifi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(hadis.text, style: const TextStyle(fontSize: 13, height: 1.45, fontStyle: FontStyle.italic)),
            const SizedBox(height: 4),
            Text(hadis.source, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ])),
          const SizedBox(height: 14),
          Center(
            child: Text('Konum: ${AppSettings.cityName} · Aile ile Namaz v$_version',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: child,
      );

  Widget _stat(String value, String label) => Expanded(
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
        ]),
      );

  Widget _status(PrayerStatus s) {
    final (bg, fg) = switch (s) {
      PrayerStatus.prayed => (AppColors.emeraldContainer, AppColors.emerald),
      PrayerStatus.missed => (const Color(0xFFFEE2E2), AppColors.missed),
      PrayerStatus.excused => (const Color(0xFFF3F4F6), AppColors.textSecondary),
      PrayerStatus.none => (const Color(0xFFF3F4F6), AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text('${s.emoji} ${s.label}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}
