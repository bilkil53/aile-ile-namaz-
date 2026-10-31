import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Güncelleme iki kanaldan yapılır (derlemede `--dart-define=STORE=` ile seçilir):
/// - `github` (varsayılan): GitHub Releases'taki son APK uygulama içinde indirilir, Android kurulum ekranı açılır.
/// - `play`: Google Play'in uygulama içi güncelleme sistemi kullanılır (Play kuralları APK indirmeyi yasaklar).
/// Karşılaştırma derleme numarasıyla yapılır (yayın etiketi rN = versionCode N).
class UpdateChecker {
  static const store = String.fromEnvironment('STORE', defaultValue: 'github');
  static bool get isPlay => store == 'play';

  static const _latestApi =
      'https://api.github.com/repos/bilkil53/aile-ile-namaz-/releases/latest';
  static const downloadUrl =
      'https://github.com/bilkil53/aile-ile-namaz-/releases/latest/download/aile-ile-namaz.apk';

  static bool _checked = false;

  /// GitHub'daki son sürüm: (numara, açıklamanın ilk satırı). Hata olursa null.
  static Future<(int, String)?> latest() async {
    if (isPlay) {
      final cur = await currentBuild();
      return await _playAvailable() ? (cur + 1, 'Google Play\'de yeni güncelleme var.') : (cur, '');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(_latestApi));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'aile-ile-namaz-app');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final tag = body['tag_name'] as String? ?? '';
      final n = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final notes = ((body['body'] as String?) ?? '').split('\n').first.trim();
      return (n, notes);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<int> currentBuild() async =>
      int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  /// Ayarlar'daki "Hemen Güncelle" için.
  static Future<void> install(BuildContext context, int version) =>
      isPlay ? _playUpdate(context) : _downloadAndInstall(context, version);

  /// Uygulama açılışında bir kez çağrılır. Hata olursa sessizce geçer.
  // ---------- Google Play ----------
  static Future<bool> _playAvailable() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      return info.updateAvailability == UpdateAvailability.updateAvailable;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _playUpdate(BuildContext context) async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      if (info.flexibleUpdateAllowed) {
        // Arka planda iner, bitince uygulama yeniden başlatılarak kurulur
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      } else if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (_) {
      await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=com.bilkil53.aile_ile_namaz'),
          mode: LaunchMode.externalApplication);
    }
  }

  static Future<void> check(BuildContext context) async {
    if (_checked || !Platform.isAndroid) return;
    _checked = true;
    if (isPlay) {
      if (await _playAvailable() && context.mounted) await _playUpdate(context);
      return;
    }
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
          title: const Text('Yeni güncelleme var'),
          content: Text(
            'Aile ile Namaz için yeni bir güncelleme hazır.'
            '${notes.isNotEmpty ? '\n\n$notes' : ''}',
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
      if (ok == true && context.mounted) {
        await _downloadAndInstall(context, latest);
      }
    } catch (_) {
      // İnternet yoksa vb. sessizce geç.
    }
  }

  static Future<void> _downloadAndInstall(BuildContext context, int version) async {
    final progress = ValueNotifier<double?>(null);
    var cancelled = false;

    // İlerleme penceresi
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Güncelleniyor'),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, p, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: p),
                const SizedBox(height: 10),
                Text(p == null ? 'İndirme başlıyor…' : 'İndiriliyor… %${(p * 100).toStringAsFixed(0)}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.pop(ctx);
              },
              child: const Text('Vazgeç'),
            ),
          ],
        ),
      ),
    ));

    final client = HttpClient();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/aile-ile-namaz-$version.apk');

      final req = await client.getUrl(Uri.parse(downloadUrl));
      req.headers.set('User-Agent', 'aile-ile-namaz-app');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');

      final total = res.contentLength;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in res) {
        if (cancelled) break;
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) progress.value = received / total;
      }
      await sink.close();
      client.close();
      if (cancelled) {
        if (await file.exists()) await file.delete();
        return;
      }

      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

      // Android'in "Bu uygulamayı güncellemek istiyor musunuz?" ekranı
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } catch (_) {
      client.close(force: true);
      if (context.mounted && !cancelled) {
        Navigator.of(context, rootNavigator: true).maybePop();
        // Son çare: tarayıcıdan indir.
        await launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.externalApplication);
      }
    } finally {
      progress.dispose();
    }
  }
}
