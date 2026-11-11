import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../lang.dart';
import '../member_icon.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/danger_box.dart';
import '../widgets/login_required.dart';
import '../widgets/prayer_icon.dart';

/// Kaza namazı takibi.
/// Hangi vakit kaza edildiği sadece sahibine görünür; aile yalnızca toplamı görür.
class KazaScreen extends StatefulWidget {
  const KazaScreen({super.key});

  @override
  State<KazaScreen> createState() => _KazaScreenState();
}

class _KazaScreenState extends State<KazaScreen> {
  // (tip, ad, emoji, farz rekat)
  static List<(String, String, String, String)> get _types => [
        ('FAJR', t('Sabah Namazı', 'Fajr Prayer'), '🌅', t('Farz: 2 Rekat', 'Fard: 2 Rakats')),
        ('DHUHR', t('Öğle Namazı', 'Dhuhr Prayer'), '☀️', t('Farz: 4 Rekat', 'Fard: 4 Rakats')),
        ('ASR', t('İkindi Namazı', 'Asr Prayer'), '⛅', t('Farz: 4 Rekat', 'Fard: 4 Rakats')),
        ('MAGHRIB', t('Akşam Namazı', 'Maghrib Prayer'), '🌇', t('Farz: 3 Rekat', 'Fard: 3 Rakats')),
        ('ISHA', t('Yatsı Namazı', 'Isha Prayer'), '🌌', t('Farz: 4 Rekat', 'Fard: 4 Rakats')),
        ('WITR', t('Vitir Namazı', 'Witr Prayer'), '⭐', t('Vacip: 3 Rekat', 'Wajib: 3 Rakats')),
      ];

  Map<String, (int, int)> _data = {};
  List<Member> _family = [];
  Member? _me;
  Member? _reis;
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
          final me = members.where((m) => m.userId == myId).firstOrNull;
          final reis = members.where((m) => m.userId == pools.first.ownerId).firstOrNull;
          final k = await Repo.kazaSummary(others.map((m) => m.userId).toList());
          if (mounted) {
            setState(() {
              _me = me;
              _reis = reis;
              _family = others;
              _familyKaza = k;
            });
          }
        }
      }
    } catch (_) {
      _toast(t('Kaza bilgisi yüklenemedi.', 'Could not load kaza info.'));
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
    if (isGuest) return showLoginRequired(context, t('Kaza kaydı tutmak', 'keep kaza records'));
    final before = _of(type);
    setState(() => _data = {..._data, type: (owed, completed)});
    try {
      await Repo.saveKaza(type, owed, completed, announce: announce);
    } catch (_) {
      if (mounted) setState(() => _data = {..._data, type: before});
      _toast(t('Kaydedilemedi.', 'Could not save.'));
    }
  }

  Future<void> _bulkAdd() async {
    if (isGuest) return showLoginRequired(context, t('Kaza kaydı tutmak', 'keep kaza records'));
    final days = await showDialog<int>(context: context, builder: (_) => const _BulkDialog());
    if (days == null || days <= 0 || days > 36500) return;
    for (final (t, _, _, _) in _types) {
      final (o, c) = _of(t);
      await _set(t, o + days, c);
    }
    _toast(days % 365 == 0 ? t('Her vakte ${days ~/ 365} yıllık ($days gün) kaza eklendi.', 'Added ${days ~/ 365} years ($days days) of kaza to each prayer.') : t('Her vakte $days gün eklendi.', 'Added $days days to each prayer.'));
  }

  /// Kaza kayıtlarını sıfırla: yanlışlıkla olmasın diye iki kez onay ister.
  Future<void> _reset() async {
    if (isGuest) return showLoginRequired(context, t('Kaza kayıtlarını sıfırlamak', 'reset kaza records'));
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true, // küçük ekran / büyük yazıda taşmasın
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: const Icon(Icons.restart_alt, color: AppColors.missed, size: 32),
        title: Text(t('Kaza kayıtları sıfırlansın mı?', 'Reset kaza records?')),
        content: Text(t('Bütün vakitlerdeki kaza borcun ve kılınan kaza sayıların 0 olacak.', 'Your kaza debt and completed kaza counts for all prayers will be set to 0.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.missed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Devam', 'Continue')),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final ctrl = TextEditingController();
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          scrollable: true, // küçük ekran / büyük yazıda taşmasın
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(t('Son onay', 'Final confirmation')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('Bu işlem geri alınamaz. Onaylamak için aşağıya SIFIRLA yaz.', 'This cannot be undone. Type RESET below to confirm.')),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(border: OutlineInputBorder(), hintText: t('SIFIRLA', 'RESET')),
              onChanged: (_) => setD(() {}),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.missed),
              onPressed: ctrl.text.trim().toUpperCase() == t('SIFIRLA', 'RESET') ? () => Navigator.pop(ctx, true) : null,
              child: Text(t('Sıfırla', 'Reset')),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (second != true) return;
    for (final (t, _, _, _) in _types) {
      await _set(t, 0, 0);
    }
    _toast(t('Kaza kayıtların sıfırlandı.', 'Your kaza records were reset.'));
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
              Text(t('📿 Kaza Namazı Takibi', '📿 Kaza Prayer Tracking'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(t('Kılamadığın vakitleri kaydet, kıldıkça düş.', 'Record the prayers you missed and reduce them as you make them up.'),
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _tile(t('Kalan Kaza Borcu', 'Kaza Remaining'), '$remaining', AppColors.goldContainer, const Color(0xFF78350F))),
                const SizedBox(width: 10),
                Expanded(child: _tile(t('Kılınan Kaza', 'Kaza Completed'), '$done', AppColors.prayedMint, AppColors.emeraldDark)),
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
              Text(owed == 0 ? t('Kayıtlı kaza borcun yok.', 'You have no recorded kaza prayers.') : t('%${(ratio * 100).round()} tamamlandı · Toplam $owed vakit', '${(ratio * 100).round()}% done · $owed prayers in total'),
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
                Text(t('👨‍👩‍👧 Aile Fertleri Kaza Durumu (Detaysız)', '👨‍👩‍👧 Family Kaza Status (Summary only)'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                for (final m in _family)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      MemberIcon(m.icon, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_me == null ? m.shownName : kinLabel(viewer: _me!, target: m, reis: _reis), style: const TextStyle(fontWeight: FontWeight.w600))),
                      Builder(builder: (_) {
                        final k = _familyKaza[m.userId];
                        final left = k == null ? 0 : (k[0] > k[1] ? k[0] - k[1] : 0);
                        return Text(
                          left == 0 ? t('Borç yok ✓', 'None left ✓') : t('Kalan $left · Kılınan ${k![1]}', 'Left $left · Done ${k[1]}'),
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
          Row(children: [
            Icon(Icons.lock_outline, size: 14, color: AppColors.textMuted),
            SizedBox(width: 6),
            Expanded(
              child: Text(t('Hangi vakti kaza ettiğin sadece sende görünür; ailen yalnızca toplamı görür.', 'Which prayers you missed is visible only to you; your family only sees the total.'),
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
            label: Text(t('Toplu Ekle (yıl veya gün)', 'Bulk Add (years or days)')),
          ),
          const SizedBox(height: 12),
          for (final t in _types) ...[_row(t), const SizedBox(height: 10)],
          const SizedBox(height: 8),
          DangerBox(
            title: t('Kaza kayıtlarını sıfırla', 'Reset kaza records'),
            subtitle: t('Tüm kaza borcu ve kılınan sayıları sıfırlanır', 'All kaza debt and completed counts are reset'),
            icon: Icons.restart_alt,
            onTap: _reset,
          ),
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

  Widget _row((String, String, String, String) row) {
    final (type, label, _, rekat) = row;
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
              Text(t('$rekat | Kılınan: $done', '$rekat | Done: $done'), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          IconButton(
            tooltip: t('Borcu azalt', 'Decrease'),
            visualDensity: VisualDensity.compact,
            onPressed: owed > done ? () => _set(type, owed - 1, done) : null,
            icon: const Icon(Icons.remove_circle_outline, color: AppColors.emerald),
          ),
          Column(children: [
            Text('$left', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            Text(t('Borç', 'Left'), style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ]),
          IconButton(
            tooltip: t('Borç ekle', 'Add'),
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
                label: Text(t('Kaza Kıldım', 'I Made Up a Kaza'), style: TextStyle(fontWeight: FontWeight.bold)),
              )
            : Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.emeraldContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(t('Kaza Borcu Yok (Elhamdülillah) 🤲', 'No Kaza Left (Alhamdulillah) 🤲'),
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
      title: Text(t('Toplu Kaza Borcu Ekle', 'Bulk Add Kaza')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(t('Yıl', 'Years')), icon: Icon(Icons.calendar_today, size: 16)),
              ButtonSegment(value: false, label: Text(t('Gün', 'Days')), icon: Icon(Icons.today, size: 16)),
            ],
            selected: {_years},
            onSelectionChanged: (v) => setState(() {
              _years = v.first;
              _ctrl.clear();
            }),
          ),
          const SizedBox(height: 12),
          if (_years) ...[
            Text(t('Hızlı ekle:', 'Quick add:'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final y in [1, 2, 3, 5, 10, 15, 20])
                ActionChip(
                  label: Text(t('$y Yıl', '$y yr')),
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
              labelText: _years ? t('Yıl sayısı', 'Number of years') : t('Gün sayısı', 'Number of days'),
              hintText: _years ? t('örn. 7', 'e.g. 7') : t('örn. 365', 'e.g. 365'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            _value > 0
                ? t('Her vakte (vitir dahil) $_days gün eklenecek · toplam ${_days * 6} vakit.', '$_days days will be added to each prayer (incl. witr) · ${_days * 6} prayers in total.')
                : (_years ? t('1 yıl = 365 gün olarak hesaplanır.', '1 year is counted as 365 days.') : t('Her vakte (vitir dahil) bu sayı eklenir.', 'This number is added to each prayer (incl. witr).')),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Vazgeç', 'Cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
          onPressed: _value > 0 ? () => Navigator.pop(context, _days) : null,
          child: Text(t('Ekle', 'Add')),
        ),
      ],
    );
  }
}
