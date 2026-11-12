import 'package:flutter/material.dart';

import '../lang.dart';
import '../pro.dart';
import '../theme.dart';

/// Küçük "Pro" rozeti (kilitli özelliklerin yanında).
class ProBadge extends StatelessWidget {
  const ProBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(6)),
        child: const Text('PRO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
      );
}

/// Kilitli özelliğe dokununca: "Bu özellik Pro sürümde" bilgisi + Pro'ya geç.
Future<void> showProRequired(BuildContext context, {String? feature}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.workspace_premium, color: AppColors.gold, size: 32),
      title: Text(t('Pro özellik', 'Pro feature')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('${feature == null ? 'Bu özellik' : '"$feature"'} Pro sürümde kullanılabilir.',
            '${feature == null ? 'This feature' : '"$feature"'} is available in the Pro version.')),
        const SizedBox(height: 8),
        Text(Pro.statusText(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Text(t('👨‍👩‍👧 Ailede bir kişinin (Aile Reisi) Pro alması yeterli; aile havuzundaki herkes (en fazla 5 kişi) Pro olur.', '👨‍👩‍👧 It is enough for one person in the family (the head of family) to get Pro; everyone in the family circle (up to 5 people) becomes Pro.'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),

        const SizedBox(height: 8),
        Text(t('ℹ️ İnternet gerektiren özellikler (aile havuzu, bildirimler, bulut yedekleme, Pro) sunucu altyapısı çalıştığı sürece kullanılabilir; bakım veya kesintide geçici olarak çalışmayabilir.', 'ℹ️ Features that need the internet (family circle, notifications, cloud backup, Pro) work as long as the server infrastructure is running; they may be temporarily unavailable during maintenance or outages.'), style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Kapat', 'Close'))),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            showProCodeDialog(context);
          },
          child: Text(t('Pro\'ya geç', 'Get Pro')),
        ),
      ],
    ),
  );
}

/// Reis olmayan üye: Pro'yu Aile Reisi alır; reise iletme penceresi.
Future<void> _showAskReisDialog(BuildContext context) async {
  var busy = false;
  final declinedAt = await Pro.myDeclinedAt();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        icon: const Icon(Icons.workspace_premium, color: AppColors.gold, size: 32),
        title: Text(t('Pro\'yu Aile Reisi alır', 'The head of family gets Pro')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t(
              '👨‍👩‍👧 Aile Reisin Pro alınca aile havuzundaki herkes (en fazla 5 kişi) Pro olur. '
                  'Senin ayrıca bir şey alman gerekmez.',
              '👨‍👩‍👧 When your head of family gets Pro, everyone in the family circle (up to 5 people) becomes Pro. '
                  'You do not need to buy anything.')),
          if (declinedAt != null) ...[
            const SizedBox(height: 8),
            Text(t('🙏 Aile Reisin ${Pro.fmt(declinedAt)} tarihinde şimdilik Pro almadı. Yarın tekrar iletebilirsin.', '🙏 Your head of family did not get Pro for now on ${Pro.fmt(declinedAt)}. You can ask again tomorrow.'),
                style: const TextStyle(fontSize: 13, color: AppColors.gold, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          Text(Pro.statusText(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),

          const SizedBox(height: 8),
          Text(t('ℹ️ İnternet gerektiren özellikler (aile havuzu, bildirimler, bulut yedekleme, Pro) sunucu altyapısı çalıştığı sürece kullanılabilir; bakım veya kesintide geçici olarak çalışmayabilir.', 'ℹ️ Features that need the internet (family circle, notifications, cloud backup, Pro) work as long as the server infrastructure is running; they may be temporarily unavailable during maintenance or outages.'), style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: Text(t('Kapat', 'Close'))),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    setLocal(() => busy = true);
                    final err = await Pro.requestFromReis();
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err ?? t('📩 Aile Reisine iletildi. Pro alınca sende de açılır.', '📩 Sent to the head of family. It opens for you too when they get Pro.'))));
                  },
            icon: const Text('📩'),
            label: Text(busy ? '...' : t('Aile Reisine ilet', 'Ask the head of family')),
          ),
        ],
      ),
    ),
  );
}

/// Pro'ya geçiş penceresi (yalnızca Aile Reisi). Reis değilse "Aile Reisine ilet" açılır.
/// Elle kod yok: Pro yalnızca ödemeyle alınır (Google Play: hattın faturası ya da kart). Play sürümü
/// çıkana kadar ödeme açık değildir; test hesabına ayrıca "Test: Pro'yu aç" düğmesi görünür.
Future<void> showProCodeDialog(BuildContext context) async {
  if (!await Pro.isReis()) {
    if (context.mounted) await _showAskReisDialog(context);
    return;
  }
  final tester = kTestChannel && await Pro.testerStatus() == true; // kararlı sürümde test düğmesi yok
  if (!context.mounted) return;
  var busy = false;
  String? err;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        icon: const Icon(Icons.workspace_premium, color: AppColors.gold, size: 32),
        title: Text(t('Pro\'ya geç', 'Get Pro')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('👨‍👩‍👧 Ailede bir kişinin (Aile Reisi) Pro alması yeterli; aile havuzundaki herkes (en fazla 5 kişi) Pro olur.', '👨‍👩‍👧 It is enough for one person in the family (the head of family) to get Pro; everyone in the family circle (up to 5 people) becomes Pro.'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(t('💳 Ödeme Google Play üzerinden alınır: hattınızın faturasına yansıtabilir ya da kartla ödeyebilirsiniz.', '💳 Payment is taken through Google Play: you can charge it to your mobile phone bill or pay by card.'), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Text(t('⏳ Ödeme, uygulamanın Google Play sürümüyle açılacak.', '⏳ Payment will open with the Google Play version of the app.'), style: const TextStyle(fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w600)),
          if (err != null) ...[
            const SizedBox(height: 8),
            Text(err!, style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: 8),
          Text(t('ℹ️ İnternet gerektiren özellikler (aile havuzu, bildirimler, bulut yedekleme, Pro) sunucu altyapısı çalıştığı sürece kullanılabilir; bakım veya kesintide geçici olarak çalışmayabilir.', 'ℹ️ Features that need the internet (family circle, notifications, cloud backup, Pro) work as long as the server infrastructure is running; they may be temporarily unavailable during maintenance or outages.'), style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: Text(t('Kapat', 'Close'))),
          if (tester)
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() {
                        busy = true;
                        err = null;
                      });
                      final ok = await Pro.redeem();
                      if (!ctx.mounted) return;
                      if (ok) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(t('Test: Pro açıldı 🎉', 'Test: Pro activated 🎉'))));
                      } else {
                        setLocal(() {
                          busy = false;
                          err = Pro.lastError ?? t('Pro açılamadı. İnternetini kontrol edip tekrar dene.', 'Could not activate Pro. Check your internet and try again.');
                        });
                      }
                    },
              child: Text(busy ? '...' : t('Test: Pro\'yu aç', 'Test: activate Pro')),
            ),
        ],
      ),
    ),
  );
}
