import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../theme.dart';

/// Kaza namazı takibi. Detay (hangi vakit) sadece sahibine görünür;
/// havuzdaki aile üyeleri yalnızca toplam sayıyı görür.
class KazaScreen extends StatefulWidget {
  const KazaScreen({super.key});

  @override
  State<KazaScreen> createState() => _KazaScreenState();
}

class _KazaScreenState extends State<KazaScreen> {
  static const _types = [
    ('FAJR', 'Sabah', Icons.wb_twilight),
    ('DHUHR', 'Öğle', Icons.wb_sunny),
    ('ASR', 'İkindi', Icons.wb_cloudy),
    ('MAGHRIB', 'Akşam', Icons.nightlight_round),
    ('ISHA', 'Yatsı', Icons.bedtime),
    ('WITR', 'Vitir', Icons.star),
  ];

  Map<String, (int, int)> _data = {};
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
    final ctrl = TextEditingController();
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Toplu borç ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Kaç günlük namaz borcun var? Her vakte (vitir dahil) bu sayı eklenir.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Gün sayısı', hintText: 'örn. 365'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (days == null || days <= 0 || days > 36500) return;
    for (final (t, _, _) in _types) {
      final (o, c) = _of(t);
      await _set(t, o + days, c);
    }
    _toast('Her vakte $days eklendi.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    var owed = 0, done = 0;
    for (final (t, _, _) in _types) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.calendar_month, size: 14, color: Colors.white),
                  SizedBox(width: 5),
                  Text('KAZA BORCU',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
                ]),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$remaining',
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('vakit kaldı',
                          style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.85))),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    color: AppColors.prayedMint,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Toplam borç $owed · Ödenen $done',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Row(children: [
            Icon(Icons.lock_outline, size: 14, color: AppColors.textMuted),
            SizedBox(width: 6),
            Expanded(
              child: Text('Hangi vakti kaza ettiğin sadece sende görünür; ailen yalnızca toplamı görür.',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _bulkAdd,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Toplu borç ekle (gün sayısıyla)'),
          ),
          const SizedBox(height: 12),
          for (final (type, label, icon) in _types) ...[
            _row(type, label, icon),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _row(String type, String label, IconData icon) {
    final (owed, done) = _of(type);
    final left = owed > done ? owed - done : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.emeraldContainer, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: AppColors.emerald),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                Text('Kalan $left · Ödenen $done',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Borcu azalt',
            visualDensity: VisualDensity.compact,
            onPressed: owed > done ? () => _set(type, owed - 1, done) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton(
            tooltip: 'Borç ekle',
            visualDensity: VisualDensity.compact,
            onPressed: () => _set(type, owed + 1, done),
            icon: const Icon(Icons.add_circle_outline),
          ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emerald,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: left > 0 ? () => _set(type, owed, done + 1, announce: true) : null,
            child: const Text('Kıldım'),
          ),
        ],
      ),
    );
  }
}
