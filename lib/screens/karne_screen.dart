import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:package_info_plus/package_info_plus.dart';

import '../data.dart';
import '../lang.dart';
import '../dini_gunler.dart';
import '../pro.dart';
import '../karne_badges.dart';
import '../notifications.dart';
import '../settings.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/prayer_icon.dart';

/// İbadet Karnesi: sadece kişinin KENDİ gelişimi (aile verisi yok), okul karnesi mantığıyla.
/// Dönem seçimi → genel not → vakit vakit karne (en çok aksatılan vakit) → seri → aylık takvim
/// → kaza ilerlemesi → kişisel rozetler.
class KarneScreen extends StatefulWidget {
  const KarneScreen({super.key});

  @override
  State<KarneScreen> createState() => _KarneScreenState();
}

enum _Period { week, month, quarter }

class _KarneScreenState extends State<KarneScreen> {
  Map<String, Map<String, PrayerStatus>> _data = {};
  Map<String, (int, int)> _kaza = {};
  String _name = '';
  String _version = '';
  bool _loading = true;
  _Period _period = _Period.week;

  void _proRebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Pro.changed.removeListener(_proRebuild);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Pro.changed.addListener(_proRebuild);
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    });
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    try {
      final r = await Future.wait<dynamic>([
        Repo.myRange(now.subtract(const Duration(days: 399)), now),
        DiniGunler.ensure(),
        Repo.myKaza(),
        Repo.myDisplayName(),
      ]);
      if (!mounted) return;
      setState(() {
        _data = r[0] as Map<String, Map<String, PrayerStatus>>;
        _kaza = r[2] as Map<String, (int, int)>;
        _name = r[3] as String;
      });
    } catch (_) {
      // çevrimdışı: eldeki veriyle göster
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _announceNewBadges();
  }

  List<KarneBadge> _badges() {
    var owed = 0, done = 0;
    for (final v in _kaza.values) {
      owed += v.$1;
      done += v.$2;
    }
    return KarneBadges(_data, owed, done).all();
  }

  /// Yeni kazanılan rozet / seviye için tebrik bildirimi (ilk açılışta sadece kaydedilir).
  Future<void> _announceNewBadges() async {
    try {
      const k = 'karne.earnedBadges';
      final earned = _badges().where((b) => b.earned).toList();
      final keys = earned.map((b) => b.key).toSet();
      final prev = AppSettings.prefs.getStringList(k);
      await AppSettings.prefs.setStringList(k, keys.toList());
      if (prev == null) return;
      final fresh = earned.where((b) => !prev.contains(b.key)).toList();
      for (var i = 0; i < fresh.length && i < 3; i++) {
        final b = fresh[i];
        final name = b.levelName.isEmpty ? b.title : '${b.title} · ${b.levelName}';
        await Notifications.showFamily(9100 + i, t('🏅 Tebrikler! Yeni rozet: $name', '🏅 Congratulations! New badge: $name'), '${b.emoji} ${b.desc}');
      }
      if (fresh.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('🏅 Yeni rozet: ', '🏅 New badge: ') + fresh.first.title + (fresh.length > 1 ? ' (+${fresh.length - 1})' : ''))));
      }
    } catch (_) {}
  }

  String _k(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  PrayerStatus _st(DateTime d, String key) => _data[_k(d)]?[key] ?? PrayerStatus.none;

  /// Dönemin günleri (bugün dahil, eskiden yeniye).
  List<DateTime> get _days {
    final n = switch (_period) { _Period.week => 7, _Period.month => 30, _Period.quarter => 90 };
    final t = DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    return [for (var i = n - 1; i >= 0; i--) today.subtract(Duration(days: i))];
  }

  /// Muaf günler hesaba katılmaz: başarı = kılınan / (toplam − muaf).
  (int prayed, int total) _score(Iterable<DateTime> days, [String? key]) {
    var p = 0, t = 0;
    for (final d in days) {
      for (final k in key == null ? prayerKeys : [key]) {
        final s = _st(d, k);
        if (s == PrayerStatus.excused) continue;
        t++;
        if (s == PrayerStatus.prayed) p++;
      }
    }
    return (p, t);
  }

  (String, Color) _grade(int pct) => pct >= 90
      ? (t('Pekiyi', 'Excellent'), AppColors.emerald)
      : pct >= 75
          ? (t('İyi', 'Good'), const Color(0xFF2E7D32))
          : pct >= 50
              ? (t('Orta', 'Fair'), AppColors.gold)
              : (t('Gayret et', 'Keep trying'), AppColors.missed);

  bool _fullDay(DateTime d) =>
      prayerKeys.every((k) => _st(d, k) == PrayerStatus.prayed || _st(d, k) == PrayerStatus.excused) &&
      prayerKeys.any((k) => _st(d, k) == PrayerStatus.prayed);

  (int current, int best) _streaks() {
    final t = DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    var cur = 0;
    // Bugün henüz tamamlanmadıysa seri dünden sayılır
    var start = _fullDay(today) ? 0 : 1;
    for (var i = start; i < 90; i++) {
      if (_fullDay(today.subtract(Duration(days: i)))) {
        cur++;
      } else {
        break;
      }
    }
    var best = 0, run = 0;
    for (var i = 89; i >= 0; i--) {
      if (_fullDay(today.subtract(Duration(days: i)))) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
    }
    return (cur, best);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final demo = Pro.isDemo; // demo: kaza kapalı olduğu için kaza bölümleri gizlenir
    final days = _days;
    final (p, tot) = _score(days);
    final pct = tot == 0 ? 0 : (p * 100 / tot).round();
    final (grade, gradeColor) = _grade(pct);
    final perPrayer = {for (final k in prayerKeys) k: _score(days, k)};
    String? weakest;
    var weakPct = 101;
    for (final k in prayerKeys) {
      final (pp, tt) = perPrayer[k]!;
      if (tt == 0) continue;
      final v = (pp * 100 / tt).round();
      if (v < weakPct) {
        weakPct = v;
        weakest = k;
      }
    }
    final (curStreak, bestStreak) = _streaks();
    var owed = 0, done = 0;
    for (final v in _kaza.values) {
      owed += v.$1;
      done += v.$2;
    }
    final kazaPct = owed == 0 ? 0.0 : (done / owed).clamp(0.0, 1.0).toDouble();
    final badges = _badges();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ---------- Başlık + dönem + genel not ----------
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.emerald, borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_name.isNotEmpty ? t('$_name · Karnesi', "$_name's Report") : t('İbadet Karnesi', 'Worship Report'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 10),
              SegmentedButton<_Period>(
                style: SegmentedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  foregroundColor: Colors.white,
                  selectedBackgroundColor: Colors.white,
                  selectedForegroundColor: AppColors.emerald,
                ),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: _Period.week, label: Text(t('Bu hafta', 'This week'))),
                  ButtonSegment(value: _Period.month, label: Text(t('30 gün', '30 days'))),
                  ButtonSegment(value: _Period.quarter, label: Text('3 ay')),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('%$pct', style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Text(grade, style: TextStyle(fontWeight: FontWeight.bold, color: gradeColor)),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(t('$p / $tot vakit', '$p / $tot prayers'),
                      style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85))),
                ),
              ]),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  color: AppColors.prayedMint,
                ),
              ),
              const SizedBox(height: 6),
              Text(t('Muaf işaretlenen vakitler hesaba katılmaz.', 'Prayers marked as excused are not counted.'),
                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
            ]),
          ),
          const SizedBox(height: 14),

          // ---------- Vakit vakit karne ----------
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('📋 Vakit Vakit Karne', '📋 Report by Prayer'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            for (final k in prayerKeys)
              Builder(builder: (_) {
                final (pp, tt) = perPrayer[k]!;
                final v = tt == 0 ? 0 : (pp * 100 / tt).round();
                final (g, c) = _grade(v);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    PrayerIcon(k, size: 16, color: AppColors.emerald, background: AppColors.emeraldContainer),
                    const SizedBox(width: 10),
                    SizedBox(width: 56, child: Text(prayerLabels[k]!, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            value: v / 100, minHeight: 8, color: c, backgroundColor: AppColors.segmentInactive),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 92,
                      child: Text('$pp/$tt · $g',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c)),
                    ),
                  ]),
                );
              }),
            if (weakest != null && weakPct < 100) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.goldContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  t('💡 En çok aksattığın vakit: ${prayerLabels[weakest]} (%$weakPct). Bu vakte biraz daha özen gösterebilirsin.',
                      '💡 The prayer you miss most: ${prayerLabels[weakest]} ($weakPct%). Try to pay a little more attention to it.'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF78350F)),
                ),
              ),
            ],
          ])),
          const SizedBox(height: 14),

          // ---------- Seri ----------
          Row(children: [
            Expanded(child: _tile('🔥', t('$curStreak gün', '$curStreak days'), t('Şu anki seri', 'Current streak'))),
            const SizedBox(width: 10),
            Expanded(child: _tile('🏅', t('$bestStreak gün', '$bestStreak days'), t('En uzun seri (3 ay)', 'Longest streak (3 months)'))),
          ]),
          const SizedBox(height: 14),

          // ---------- Aylık takvim ----------
          _card(_calendar()),
          const SizedBox(height: 14),

          // ---------- Kaza ilerlemesi (demo'da gizli) ----------
          if (!demo) _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('📿 Kaza İlerlemen', '📿 Your Kaza Progress'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (owed == 0)
              Text(t('Kayıtlı kaza borcun yok.', 'You have no recorded kaza prayers.'), style: TextStyle(color: AppColors.textSecondary))
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: kazaPct, minHeight: 10, color: AppColors.emerald, backgroundColor: AppColors.segmentInactive),
              ),
              const SizedBox(height: 6),
              Text(t('$done / $owed eda edildi · %${(kazaPct * 100).round()} · kalan ${owed - done}',
                    '$done / $owed made up · ${(kazaPct * 100).round()}% · ${owed - done} left'),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ])),
          const SizedBox(height: 14),

          // ---------- Kişisel rozetler (demo'da gizli) ----------
          if (!demo) ...[
          Text(t('🏅 Manevi Rozetler', '🏅 Spiritual Badges'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          if (badges.any((b) => b.seasonal)) ...[
            Text(t('Mübarek günler', 'Blessed days'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            for (final b in badges.where((b) => b.seasonal)) _badgeTile(b),
            const SizedBox(height: 6),
          ],
          // Temel rozetler (her zaman): seviyesiz ve mübarek gün olmayanlar
          for (final b in badges.where((b) => b.earned && !b.seasonal && b.tiers == null)) _badgeTile(b),
          for (final b in badges.where((b) => !b.earned && !b.seasonal && b.tiers == null)) _badgeTile(b),
          for (final b in badges.where((b) => b.tiers != null)) _badgeTile(b),
          ],
          const SizedBox(height: 10),
          Center(
            child: Text(t('Karne sadece senin kayıtlarından hazırlanır · Aile ile Namaz v$_version', 'The report is built only from your own records · Aile ile Namaz v$_version'),
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }


  static const _tierColors = [Color(0xFFB0703C), Color(0xFF8A94A0), Color(0xFFC8961E), Color(0xFF3B9BB3)];

  /// Rozet satırı: kazanılan altın zeminde (seviyeli ise Bronz/Gümüş/Altın/Elmas etiketi),
  /// kazanılmayan soluk ve altında ilerleme çubuğu.
  Widget _badgeTile(KarneBadge b) {
    final next = b.nextTarget;
    final prog = next == 0 ? 0.0 : (b.value / next).clamp(0.0, 1.0).toDouble();
    final showBar = !b.maxed && next > 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: b.earned ? AppColors.goldContainer : AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: b.earned ? AppColors.gold : AppColors.cardBorder),
      ),
      child: Row(children: [
        Opacity(opacity: b.earned ? 1 : 0.35, child: Text(b.emoji, style: const TextStyle(fontSize: 26))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(b.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              if (b.levelName.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: _tierColors[b.level - 1], borderRadius: BorderRadius.circular(6)),
                  child: Text(b.levelName,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ]),
            Text(b.desc, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            if (showBar) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                    value: prog, minHeight: 5, color: AppColors.gold, backgroundColor: AppColors.segmentInactive),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Text(
            b.maxed
                ? t('Kazanıldı ✓', 'Earned ✓')
                : next == 1
                    ? (b.earned ? t('Kazanıldı ✓', 'Earned ✓') : t('Henüz yok', 'Not yet'))
                    : '${b.value.clamp(0, next)}/$next',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: b.earned ? const Color(0xFF78350F) : AppColors.textMuted)),
      ]),
    );
  }

  /// Bu ayın takvimi: her gün renkli kare (5/5 koyu yeşil, kısmi açık, kılınmadı kırmızı, boş gri).
  Widget _calendar() {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final lead = first.weekday - 1; // Pazartesi başlar
    Color colorFor(DateTime d) {
      if (d.isAfter(now)) return Colors.transparent;
      final prayed = prayerKeys.where((k) => _st(d, k) == PrayerStatus.prayed).length;
      final missed = prayerKeys.where((k) => _st(d, k) == PrayerStatus.missed).length;
      if (_fullDay(d)) return AppColors.emerald;
      if (prayed > 0) return AppColors.prayedMint;
      if (missed > 0) return AppColors.missedCoral;
      return AppColors.segmentInactive;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('🗓 ${DateFormat('MMMM y', Lang.code).format(now)}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Row(children: [
        for (final w in const ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'])
          Expanded(
              child: Text(w,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
      ]),
      const SizedBox(height: 4),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        children: [
          for (var i = 0; i < lead; i++) const SizedBox(),
          for (var d = 1; d <= daysInMonth; d++)
            Builder(builder: (_) {
              final day = DateTime(now.year, now.month, d);
              final c = colorFor(day);
              final today = d == now.day;
              return Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(6),
                  border: today ? Border.all(color: AppColors.gold, width: 2) : null,
                ),
                child: Text('$d',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c == AppColors.emerald ? Colors.white : AppColors.textPrimary)),
              );
            }),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 4, children: [
        _legend(AppColors.emerald, t('5 vakit', 'All 5')),
        _legend(AppColors.prayedMint, t('Kısmen', 'Partly')),
        _legend(AppColors.missedCoral, t('Kılınmadı', 'Missed')),
        _legend(AppColors.segmentInactive, t('İşaretsiz', 'Unmarked')),
      ]),
    ]);
  }

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ]);

  Widget _tile(String emoji, String value, String label) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ]),
      );

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: child,
      );
}
