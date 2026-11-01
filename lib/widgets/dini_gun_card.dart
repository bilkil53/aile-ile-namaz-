import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data.dart';
import '../dini_gunler.dart';
import '../theme.dart';

/// Bugün ekranının en üstünde: bayram günlerinde büyük bayram kartı,
/// kandil / mübarek gün olan günlerde sade bilgi kartı. Başka günlerde hiçbir şey göstermez.
class DiniGunCard extends StatefulWidget {
  /// Önizleme: gerçek tarihe bakmadan bu günü gösterir (Ayarlar > önizleme).
  final DiniGun? preview;
  final int previewDay;
  const DiniGunCard({super.key, this.preview, this.previewDay = 1});

  @override
  State<DiniGunCard> createState() => _DiniGunCardState();
}

class _DiniGunCardState extends State<DiniGunCard> {
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    DiniGunler.ensure().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _sendFamily(String text) async {
    if (isGuest) return _toast('Aileye göndermek için Google ile giriş yap.');
    setState(() => _sending = true);
    try {
      final pools = await Repo.myPools().timeout(const Duration(seconds: 6));
      if (pools.isEmpty) {
        _toast('Henüz bir aile havuzunda değilsin.');
      } else {
        await Repo.sendDua(pools.first.id, text).timeout(const Duration(seconds: 8));
        _toast('Aileye gönderildi 🤲');
      }
    } catch (_) {
      _toast('Gönderilemedi. Biraz sonra tekrar dene.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    if (p != null) return p.bayram ? _bayram(p, widget.previewDay) : _special(p);
    final now = DateTime.now();
    final b = DiniGunler.bayramOn(now);
    if (b != null) return _bayram(b.$1, b.$2);
    final s = DiniGunler.specialOn(now);
    if (s != null) return _special(s);
    return const SizedBox.shrink();
  }

  Widget _bayram(DiniGun g, int dayNo) {
    final msg = '${g.emoji} ${g.name}nız mübarek olsun! Allah nice bayramlara sağlık, huzur ve '
        'birlik içinde ulaştırsın. 🤲';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(color: AppColors.emerald, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Text(g.emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${g.name}nız mübarek olsun',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('Bayramın $dayNo. günü · ${g.days} gün sürer',
                    style: const TextStyle(fontSize: 12, color: AppColors.prayedMint)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text(g.meaning, style: TextStyle(fontSize: 13, height: 1.5, color: Colors.white.withValues(alpha: 0.92))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.goldContainer,
                  foregroundColor: const Color(0xFF78350F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Share.share(msg, subject: g.name),
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Bayramlaş', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _sending ? null : () => _sendFamily(msg),
                icon: const Icon(Icons.groups, size: 16),
                label: Text(_sending ? 'Gönderiliyor…' : 'Aileye gönder'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _special(DiniGun g) {
    final title = g.eveBefore ? 'Bu akşam ${g.name}' : 'Bugün ${g.name}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(g.meaning, style: const TextStyle(fontSize: 12, height: 1.45, color: AppColors.textSecondary)),
            ]),
          ),
        ]),
      ),
    );
  }
}
