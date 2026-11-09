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

/// Kilitli özelliğe dokununca: "Bu özellik Pro sürümde" bilgisi + Pro kodu girme.
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

/// Pro kodu girme penceresi (yalnızca Aile Reisi). Reis değilse "Aile Reisine ilet" açılır.
Future<void> showProCodeDialog(BuildContext context) async {
  if (!await Pro.isReis()) {
    if (context.mounted) await _showAskReisDialog(context);
    return;
  }
  if (!context.mounted) return;
  final ctrl = TextEditingController();
  var busy = false;
  String? err;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(t('Pro kodu', 'Pro code')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: t('Kodu yaz', 'Enter the code'), errorText: err),
            onChanged: (_) => setLocal(() => err = null),
          ),
          const SizedBox(height: 10),
          Text(t('👨‍👩‍👧 Ailede bir kişinin (Aile Reisi) Pro alması yeterli; aile havuzundaki herkes (en fazla 5 kişi) Pro olur.', '👨‍👩‍👧 It is enough for one person in the family (the head of family) to get Pro; everyone in the family circle (up to 5 people) becomes Pro.'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),

          const SizedBox(height: 8),
          Text(t('ℹ️ İnternet gerektiren özellikler (aile havuzu, bildirimler, bulut yedekleme, Pro) sunucu altyapısı çalıştığı sürece kullanılabilir; bakım veya kesintide geçici olarak çalışmayabilir.', 'ℹ️ Features that need the internet (family circle, notifications, cloud backup, Pro) work as long as the server infrastructure is running; they may be temporarily unavailable during maintenance or outages.'), style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: Text(t('Vazgeç', 'Cancel'))),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setLocal(() => busy = true);
                    final ok = await Pro.redeem(ctrl.text);
                    if (!ctx.mounted) return;
                    if (ok) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(t('Pro etkinleştirildi 🎉', 'Pro activated 🎉'))));
                    } else {
                      setLocal(() {
                        busy = false;
                        err = Pro.lastError ?? t('Kod geçersiz', 'Invalid code');
                      });
                    }
                  },
            child: Text(busy ? '...' : t('Etkinleştir', 'Activate')),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
}
