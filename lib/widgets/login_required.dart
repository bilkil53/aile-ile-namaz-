import 'package:flutter/material.dart';

import '../local_store.dart';
import '../theme.dart';

/// Gezinti (misafir) modu yalnızca uygulamayı tanımak içindir: işaretleme ve kayıt yapılmaz.
/// Kayıt gerektiren bir işleme dokunulunca bu pencere çıkar; "Giriş Yap" giriş ekranına döner.
Future<void> showLoginRequired(BuildContext context, String what) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: const Text('🔐', style: TextStyle(fontSize: 34)),
      title: const Text('Google Girişi Gerekir', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      content: Text(
        '$what için Google ile giriş yapmalısın.\n\n'
        'Gezinti modu yalnızca uygulamayı tanımak içindir: ekranlara bakabilirsin, '
        'ama işaretleme ve kayıt yapılmaz. Giriş yaptıktan sonra kayıtlarını kendi hesabına girebilirsin.',
        style: const TextStyle(fontSize: 13, height: 1.4),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Gezinmeye Devam')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Google ile Giriş Yap'),
        ),
      ],
    ),
  );
  if (go == true) await LocalStore.setGuestMode(false);
}
