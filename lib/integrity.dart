import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// APK imza kontrolü: uygulama kendi imzasının parmak izini (SHA-256) okur ve
/// derleme sırasında gömülen beklenen değerle karşılaştırır. Başkası APK'yı
/// değiştirip kendi imzasıyla yeniden imzalarsa parmak izi tutmaz.
///
/// ŞİMDİLİK SADECE UYARI: uygulama kapanmaz, yalnızca bir kez uyarı gösterir.
/// İleride sağlam çalıştığı görülünce engellemeye çevrilebilir.
class Integrity {
  static const _ch = MethodChannel('aile/exit');

  /// Derlemede --dart-define=EXPECTED_SIG ile gömülür. Birden çok geçerli imza
  /// virgülle verilebilir (GitHub imzası + Google Play imzası). Boşsa kontrol yapılmaz.
  static const _expected = String.fromEnvironment('EXPECTED_SIG');

  static bool _checked = false;

  static Future<void> check(BuildContext context) async {
    if (_checked || _expected.trim().isEmpty) return;
    _checked = true;
    try {
      final sig = (await _ch.invokeMethod<String>('signatureSha256'))?.toLowerCase().trim();
      if (sig == null || sig.isEmpty) return; // okunamadıysa sessiz geç
      final valid = _expected.toLowerCase().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
      if (valid.contains(sig)) return; // imza geçerli
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.gpp_maybe_outlined, color: AppColors.missed, size: 32),
          title: const Text('Güvenlik uyarısı'),
          content: const Text(
            'Bu uygulama bilinen güvenli kaynaktan kurulmamış ya da üzerinde değişiklik yapılmış olabilir. '
            'Güvenliğin için uygulamayı resmi bağlantıdan yeniden kurmanı öneririz.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Yine de devam et')),
          ],
        ),
      );
    } catch (_) {
      // Kanal yoksa / okunamadıysa sessiz geç
    }
  }
}
