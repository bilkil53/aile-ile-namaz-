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
      content: Text(
        '${feature == null ? 'Bu özellik' : '"$feature"'} Pro sürümde kullanılabilir. '
        'Deneme sürenin bitmesinin ardından Pro koduyla tekrar açabilirsin.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            showProCodeDialog(context);
          },
          child: const Text('Pro kodu gir'),
        ),
      ],
    ),
  );
}

/// Pro kodu girme penceresi.
Future<void> showProCodeDialog(BuildContext context) async {
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
                        err = 'Kod geçersiz';
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
