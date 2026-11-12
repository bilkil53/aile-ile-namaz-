import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../lang.dart';
import '../data.dart';
import '../content/family_message.dart';
import '../dini_gunler.dart';
import '../pro.dart';
import '../theme.dart';
import 'pro_lock.dart';

/// Bugün ekranının en üstünde: bayram günlerinde büyük bayram kartı,
/// kandil / mübarek gün olan günlerde sade bilgi kartı; mübarek günden 1 gün önce
/// "yarın" bilgi kartı (bugünkü özel gün kartı varsa onun altında). Başka günlerde hiçbir şey göstermez.
class DiniGunCard extends StatefulWidget {
  /// [now]: yalnızca önizleme/test için başka bir günü göstermek (verilmezse bugün).
  const DiniGunCard({super.key, this.now, this.preview, this.previewTomorrow = false});

  final DateTime? now;

  /// Önizleme (test paneli): takvime ve internete bakmadan bu günün kartını çizer.
  /// [previewTomorrow] doğruysa "1 gün önce" kartı, değilse o günün kartı.
  final DiniGun? preview;
  final bool previewTomorrow;

  @override
  State<DiniGunCard> createState() => _DiniGunCardState();
}

class _DiniGunCardState extends State<DiniGunCard> {
  String? _sendingKey; // hangi günün tebriği gönderiliyor (arefede iki kart birlikte görünür)

  @override
  void initState() {
    super.initState();
    DiniGunler.ensure().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _openDiyanet() async {
    try {
      final ok = await launchUrl(Uri.parse('https://www.diyanet.gov.tr'), mode: LaunchMode.externalApplication);
      if (!ok) _toast(t('Bağlantı açılamadı.', 'Could not open the link.'));
    } catch (_) {
      _toast(t('Bağlantı açılamadı.', 'Could not open the link.'));
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _sendFamily(DiniGun g) async {
    if (isGuest) return _toast(t('Aileye göndermek için Google ile giriş yap.', 'Sign in with Google to send it to your family.'));
    // Ücretsiz sürümde aileye gönderme yok (sunucu da iletmez): "gönderildi" sanılmasın
    if (Pro.isDemo) return showProRequired(context, feature: t('Aileye tebrik gönderme', 'Sending greetings to family'));
    final text = diniGunMessageTr(g);
    // Tek dokunuşla tüm aileye bildirim gider: önce metni gösterip sor
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Aileye gönderilsin mi?', 'Send to your family?')),
        content: Text(t(text, diniGunMessageEn(g))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Gönder', 'Send'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _sendingKey = g.key);
    try {
      final pools = await Repo.myPools().timeout(const Duration(seconds: 6));
      if (pools.isEmpty) {
        _toast(t('Henüz bir aile havuzunda değilsin.', 'You are not in a family circle yet.'));
      } else {
        await Repo.sendDua(pools.first.id, text).timeout(const Duration(seconds: 8));
        _toast(t('Aileye gönderildi 🤲', 'Sent to your family 🤲'));
      }
    } catch (e) {
      _toast(e.toString().contains('rate_limited')
          ? t('Çok sık gönderdin. Biraz bekleyip tekrar dene.', 'You sent too often. Wait a little and try again.')
          : t('Gönderilemedi. Biraz sonra tekrar dene.', 'Could not send. Try again a bit later.'));
    } finally {
      if (mounted) setState(() => _sendingKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pv = widget.preview;
    if (pv != null) {
      if (widget.previewTomorrow) return _upcoming(pv);
      return pv.bayram ? _bayram(pv, 1) : _special(pv);
    }
    final now = widget.now ?? DateTime.now();
    final b = DiniGunler.bayramOn(now);
    if (b != null) return _bayram(b.$1, b.$2);
    final s = DiniGunler.specialOn(now);
    final u = DiniGunler.upcoming(now);
    // Arefe gibi günlerde bugünkü kartın altında yarınki (ör. bayram) kartı da görünür
    if (s != null && u != null) {
      // İki kartta ayrı ayrı tebrik düğmesi olmasın: tebrik bugünkü (arefe) kartta
      return Column(mainAxisSize: MainAxisSize.min, children: [_special(s), _upcoming(u.$1, share: false)]);
    }
    if (s != null) return _special(s);
    if (u != null) return _upcoming(u.$1);
    return const SizedBox.shrink();
  }

  /// Beyaz kartlarda (kandil, mübarek gün, "yarın") paylaşma ve aileye gönderme düğmeleri.
  Widget _shareRow(DiniGun g) {
    final msg = t(diniGunMessageTr(g), diniGunMessageEn(g));
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emerald,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Share.share(msg, subject: g.name),
            icon: const Icon(Icons.share, size: 16),
            label: Text(g.bayram ? t('Bayramlaş', 'Send Eid greetings') : t('Tebrik et', 'Send greetings'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.emerald,
              side: const BorderSide(color: AppColors.emerald),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _sendingKey != null ? null : () => _sendFamily(g),
            icon: const Icon(Icons.groups, size: 16),
            label: Text(_sendingKey == g.key ? t('Gönderiliyor…', 'Sending…') : t('Aileye gönder', 'Send to family')),
          ),
        ),
      ]),
    );
  }

  Widget _bayram(DiniGun g, int dayNo) {
    // Ekranda ve paylaşımda seçilen dilde; aileye her zaman Türkçesi gider, alıcı kendi dilinde görür
    final msg = t(bayramMessageTr(g), bayramMessageEn(g));
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
                Text(t('${g.name}nız mübarek olsun', '${g.name} Mubarak'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                Text(t('Bayramın $dayNo. günü · ${g.days} gün sürer', 'Day $dayNo of Eid · lasts ${g.days} days'),
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
                label: Text(t('Bayramlaş', 'Send Eid greetings'), style: TextStyle(fontWeight: FontWeight.bold)),
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
                onPressed: _sendingKey != null ? null : () => _sendFamily(g),
                icon: const Icon(Icons.groups, size: 16),
                label: Text(_sendingKey == g.key ? t('Gönderiliyor…', 'Sending…') : t('Aileye gönder', 'Send to family')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  /// Mübarek günden 1 gün önce açılır ("Yarın akşam" / "Yarın"); anlam ve önemini gösterir.
  Widget _upcoming(DiniGun g, {bool share = true}) {
    final when = g.eveBefore ? t('Yarın akşam', 'Tomorrow evening') : t('Yarın', 'Tomorrow');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(g.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.emerald, borderRadius: BorderRadius.circular(999)),
              child: Text(when, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(t('Anlamı ve önemi', 'Meaning and significance'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(g.meaning, style: const TextStyle(fontSize: 12, height: 1.45, color: AppColors.textSecondary)),
          InkWell(
            onTap: _openDiyanet,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(t('Tarih Diyanet takvimine göredir · Ayrıntılı bilgi: diyanet.gov.tr', 'Date follows the Diyanet calendar · More: diyanet.gov.tr'),
                  style: TextStyle(fontSize: 11, color: AppColors.emerald, decoration: TextDecoration.underline)),
            ),
          ),
          if (share) _shareRow(g),
        ]),
      ),
    );
  }

  Widget _special(DiniGun g) {
    final title = g.eveBefore ? t('Bu akşam ${g.name}', 'Tonight: ${g.name}') : t('Bugün ${g.name}', 'Today: ${g.name}');
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
              _shareRow(g),
            ]),
          ),
        ]),
      ),
    );
  }
}
