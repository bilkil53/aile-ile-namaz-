import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// GitHub Releases'taki en son APK'yı kontrol eder.
/// Her derlemede sürüm numarası = GitHub Actions çalışma numarası (apk-N etiketi).
class UpdateChecker {
  static const _latestApi =
      'https://api.github.com/repos/bilkil53/aile-ile-namaz-/releases/latest';
  static const downloadUrl =
      'https://github.com/bilkil53/aile-ile-namaz-/releases/latest/download/aile-ile-namaz.apk';

  static bool _checked = false;

  /// Uygulama açılışında bir kez çağrılır. Hata olursa sessizce geçer.
  static Future<void> check(BuildContext context) async {
    if (_checked || !Platform.isAndroid) return;
    _checked = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(_latestApi));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'aile-ile-namaz-app');
      final res = await req.close();
      if (res.statusCode != 200) {
        client.close();
        return;
      }
      final body = jsonDecode(await res.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      client.close();

      final tag = body['tag_name'] as String? ?? '';
      final latest = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (latest <= current) return;

      final notes = ((body['body'] as String?) ?? '').split('\n').first.trim();
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Yeni sürüm var'),
          content: Text(
            'Sürüm $latest yayınlandı (sizdeki: $current).'
            '${notes.isNotEmpty ? '\n\n$notes' : ''}'
            '\n\nİndirilen dosyaya dokunup "Güncelle" demeniz yeterli.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Sonra'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Güncelle'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await launchUrl(
          Uri.parse(downloadUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {
      // İnternet yoksa vb. sessizce geç.
    }
  }
}
