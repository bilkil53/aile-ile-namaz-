import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/prayer_icon.dart';

/// Kaza namazı takibi (eski uygulamadaki düzen).
/// Hangi vakit kaza edildiği sadece sahibine görünür; aile yalnızca toplamı görür.
class KazaScreen extends StatefulWidget {
  const KazaScreen({super.key});

  @override
  State<KazaScreen> createState() => _KazaScreenState();
}

class _KazaScreenState extends State<KazaScreen> {
  // (tip, ad, emoji, farz rekat)
  static const _types = [
    ('FAJR', 'Sabah Namazı', '🌅', 'Farz: 2 Rekat'),
    ('DHUHR', 'Öğle Namazı', '☀️', 'Farz: 4 Rekat'),
    ('ASR', 'İkindi Namazı', '⛅', 'Farz: 4 Rekat'),
    ('MAGHRIB', 'Akşam Namazı', '🌇', 'Farz: 3 Rekat'),
    ('ISHA', 'Yatsı Namazı', '🌌', 'Farz: 4 Rekat'),
    ('WITR', 'Vitir Namazı', '⭐', 'Vacip: 3 Rekat'),
  ];

  Map<String, (int, int)> _data = {};
  List<Member> _family = [];
  bool _iAmReis = false;
  Map<String, List<int>> _familyKaza = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Repo.myKaza();
      if (mounted) setState(() => _data = d);
      if (!isGuest) {
        final pools = await Repo.myPools();
        if (pools.isNotEmpty) {
          final members = await Repo.members(pools.first.id);
          final others = members.where((m) => m.userId != myId).toList();
          final k = await Repo.kazaSummary(others.map((m) => m.userId).toList());
          if (mounted) {
            setState(() {
              _iAmReis = pools.first.ownerId == myId;
              _family = others;
              _familyKaza = k;
            });
          }
        }
      }
    } catch (_) {
      _toast('Kaza bilgisi yüklenemedi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  (int, int) _of(String t) => _data[t] ?? (0, 0);

  Future<void> _set(String type, int owed, int completed, {bool announce = false}) async {
    final before = _of(type);
    setState(() => _data = {..._data, type: (owed, completed)});
    try {
      await Repo.saveKaza(type, owed, completed, announce: announce);
    } catch (_) {
      if (mounted) setState(() => _data = {..._data, type: before});
      _toast('Kaydedilemedi.');
    }
  }

  Future<void> _bulkAdd() async {
    final days = await showDialog<int>(context: context, builder: (_) => const _BulkDialog());
    if (days == null || days <= 0 || days > 36500) return;
    for (final (t, _, _, _) in _types) {
      final (o, c) = _of(t);
      await _set(t, o + days, c);
    }
    _toast(days % 365 == 0 ? 'Her vakte ${days ~/ 365} yıllık ($days gün) kaza eklendi.' : 'Her vakte $days gün eklendi.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    var owed = 0, done = 0;
    for (final (t, _, _, _) in _types) {
      final (o, c) = _of(t);
      owed += o;
      done += c;
    }
    final remaining = owed > done ? owed - done : 0;
    final ratio = owed == 0 ? 0.0 : (done / owed).clamp(0.0, 1.0).toDouble();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.emerald, borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('📿 Kaza Namazı Takibi',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('Kılamadığın vakitleri kaydet, kıldıkça düş.',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _tile('Kalan Kaza Borcu', '$remaining', AppColors.goldContainer, const Color(0xFF78350F))),
                const SizedBox(width: 10),
                Expanded(child: _tile('Kılınan Kaza', '$done', AppColors.prayedMint, AppColors.emeraldDark)),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  color: AppColors.prayedMint,
                ),
              ),
              const SizedBox(height: 6),
              Text(owed == 0 ? 'Kayıtlı kaza borcun yok.' : '%${(ratio * 100).round()} tamamlandı · Toplam $owed vakit',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
            ]),
          ),
          if (_family.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('👨‍👩‍👧 Aile Fertleri Kaza Durumu (Detaysız)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                for (final m in _family)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Text(m.icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(m.labelFor(viewerIsReis: _iAmReis), style: const TextStyle(fontWeight: FontWeight.w600))),
                      Builder(builder: (_) {
                        final k = _familyKaza[m.userId];
                        final left = k == null ? 0 : (k[0] > k[1] ? k[0] - k[1] : 0);
                        return Text(
                          left == 0 ? 'Borç yok ✓' : 'Kalan $left · Kılınan ${k![1]}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: left == 0 ? AppColors.emerald : AppColors.gold),
                        );
                      }),
                    ]),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          const Row(children: [
            Icon(Icons.lock_outline, size: 14, color: AppColors.textMuted),
            SizedBox(width: 6),
            Expanded(
              child: Text('Hangi vakti kaza ettiğin sadece sende görünür; ailen yalnızca toplamı görür.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.emerald,
              side: const BorderSide(color: AppColors.emerald),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _bulkAdd,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Toplu Ekle (yıl veya gün)'),
          ),
          const SizedBox(height: 12),
          for (final t in _types) ...[_row(t), const SizedBox(height: 10)],
        ],
      ),
    );
  }

  Widget _tile(String label, String value, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: fg)),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ]),
      );

  Widget _row((String, String, String, String) t) {
    final (type, label, _, rekat) = t;
    final (owed, done) = _of(type);
    final left = owed > done ? owed - done : 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.emeraldContainer, borderRadius: BorderRadius.circular(12)),
            child: PrayerIcon(type, size: 22, color: AppColors.emerald),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              Text('$rekat | Kılınan: $done', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          IconButton(
            tooltip: 'Borcu azalt',
            visualDensity: VisualDensity.compact,
            onPressed: owed > done ? () => _set(type, owed - 1, done) : null,
            icon: const Icon(Icons.remove_circle_outline, color: AppColors.emerald),
          ),
          Column(children: [
            Text('$left', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const Text('Borç', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ]),
          IconButton(
            tooltip: 'Borç ekle',
            visualDensity: VisualDensity.compact,
            onPressed: () => _set(type, owed + 1, done),
            icon: const Icon(Icons.add_circle_outline, color: AppColors.emerald),
          ),
        ]),
        const SizedBox(height: 8),
        left > 0
            ? FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _set(type, owed, done + 1, announce: true),
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('Kaza Kıldım', style: TextStyle(fontWeight: FontWeight.bold)),
              )
            : Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.emeraldContainer, borderRadius: BorderRadius.circular(12)),
                child: const Text('Kaza Borcu Yok (Elhamdülillah) 🤲',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.emerald)),
              ),
      ]),
    );
  }
}

/// Toplu kaza ekleme: gün ya da yıl olarak (1 yıl = 365 gün; her vakte, vitir dahil eklenir).
class _BulkDialog extends StatefulWidget {
  const _BulkDialog();

  @override
  State<_BulkDialog> createState() => _BulkDialogState();
}

class _BulkDialogState extends State<_BulkDialog> {
  bool _years = true;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(_ctrl.text) ?? 0;
  int get _days => _years ? _value * 365 : _value;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Toplu Kaza Borcu Ekle'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Yıl'), icon: Icon(Icons.calendar_today, size: 16)),
              ButtonSegment(value: false, label: Text('Gün'), icon: Icon(Icons.today, size: 16)),
            ],
            selected: {_years},
            onSelectionChanged: (v) => setState(() {
              _years = v.first;
              _ctrl.clear();
            }),
          ),
          const SizedBox(height: 12),
          if (_years) ...[
            const Text('Hızlı ekle:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final y in [1, 2, 3, 5, 10, 15, 20])
                ActionChip(
                  label: Text('$y Yıl'),
                  onPressed: () => Navigator.pop(context, y * 365),
                ),
            ]),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _years ? 'Yıl sayısı' : 'Gün sayısı',
              hintText: _years ? 'örn. 7' : 'örn. 365',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            _value > 0
                ? 'Her vakte (vitir dahil) $_days gün eklenecek · toplam ${_days * 6} vakit.'
                : (_years ? '1 yıl = 365 gün olarak hesaplanır.' : 'Her vakte (vitir dahil) bu sayı eklenir.'),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
          onPressed: _value > 0 ? () => Navigator.pop(context, _days) : null,
          child: const Text('Ekle'),
        ),
      ],
    );
  }
}
