import 'package:flutter/material.dart';

import '../lang.dart';
import '../local_store.dart';
import '../theme.dart';

/// Gezinti (misafir) modu yalnızca uygulamayı tanımak içindir: işaretleme ve kayıt yapılmaz.
/// Kayıt gerektiren bir işleme dokunulunca bu pencere çıkar; "Giriş Yap" giriş ekranına döner.
Future<void> showLoginRequired(BuildContext context, String what) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      scrollable: true, // küçük ekran / büyük yazıda taşmasın
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: const Text('🔐', style: TextStyle(fontSize: 34)),
      title: Text(t('Google Girişi Gerekir', 'Google Sign-in Required'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      content: Text(
        t(
          '$what için Google ile giriş yapmalısın.\n\n'
              'Gezinti modu yalnızca uygulamayı tanımak içindir: ekranlara bakabilirsin, '
              'ama işaretleme ve kayıt yapılmaz. Giriş yaptıktan sonra kayıtlarını kendi hesabına girebilirsin.',
          'Sign in with Google to $what.\n\n'
              'Browsing mode is only for getting to know the app: you can look at the screens, '
              'but nothing is marked or saved. After signing in you can keep your records in your own account.',
        ),
        style: const TextStyle(fontSize: 13, height: 1.4),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Gezinmeye Devam', 'Keep Browsing'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(t('Google ile Giriş Yap', 'Sign in with Google')),
        ),
      ],
    ),
  );
  if (go == true) await LocalStore.setGuestMode(false);
}
