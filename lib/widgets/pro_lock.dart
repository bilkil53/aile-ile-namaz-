import 'package:flutter/material.dart';

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
      title: const Text('Pro özellik'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${feature == null ? 'Bu özellik' : '"$feature"'} Pro sürümde kullanılabilir.'),
        const SizedBox(height: 8),
        Text(Pro.statusText(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        const Text('👨‍👩‍👧 Ailede bir kişinin (Aile Reisi) Pro alması yeterli; aile havuzundaki herkes (en fazla 5 kişi) Pro olur.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),

        const SizedBox(height: 8),
        const Text('ℹ️ İnternet gerektiren özellikler (aile havuzu, bildirimler, bulut yedekleme, Pro) sunucu altyapısı çalıştığı sürece kullanılabilir; bakım veya kesintide geçici olarak çalışmayabilir.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            showProCodeDialog(context);
          },
          child: const Text('Pro\'ya geç'),
        ),
      ],
    ),
  );
}

/// Reis olmayan üye: Pro'yu Aile Reisi alır; reise iletme penceresi.
Future<void> _showAskReisDialog(BuildContext context) async {
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        icon: const Icon(Icons.workspace_premium, color: AppColors.gold, size: 32),
        title: const Text('Pro\'yu Aile Reisi alır'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('👨‍👩‍👧 Aile Reisin Pro alınca aile havuzundaki herkes (en fazla 5 kişi) Pro olur. '
              'Senin ayrıca bir şey alman gerekmez.'),
          const SizedBox(height: 8),
          Text(Pro.statusText(), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),

          const SizedBox(height: 8),
          const Text('ℹ️ İnternet gerektiren özellikler (aile havuzu, bildirimler, bulut yedekleme, Pro) sunucu altyapısı çalıştığı sürece kullanılabilir; bakım veya kesintide geçici olarak çalışmayabilir.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Kapat')),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () async {
                    setLocal(() => busy = true);
                    final err = await Pro.requestFromReis();
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(err ?? '📩 Aile Reisine iletildi. Pro alınca sende de açılır.')));
                  },
            icon: const Text('📩'),
            label: Text(busy ? '...' : 'Aile Reisine ilet'),
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
        title: const Text('Pro kodu'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: 'Kodu yaz', errorText: err),
            onChanged: (_) => setLocal(() => err = null),
          ),
          const SizedBox(height: 10),
          const Text('👨‍👩‍👧 Ailede bir kişinin (Aile Reisi) Pro alması yeterli; aile havuzundaki herkes (en fazla 5 kişi) Pro olur.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),

          const SizedBox(height: 8),
          const Text('ℹ️ İnternet gerektiren özellikler (aile havuzu, bildirimler, bulut yedekleme, Pro) sunucu altyapısı çalıştığı sürece kullanılabilir; bakım veya kesintide geçici olarak çalışmayabilir.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ]),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Vazgeç')),
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
                          .showSnackBar(const SnackBar(content: Text('Pro etkinleştirildi 🎉')));
                    } else {
                      setLocal(() {
                        busy = false;
                        err = Pro.lastError ?? 'Kod geçersiz';
                      });
                    }
                  },
            child: Text(busy ? '...' : 'Etkinleştir'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
}
