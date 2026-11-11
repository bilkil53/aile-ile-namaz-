import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'lang.dart';
import 'log.dart';

/// Güncelleme iki kanaldan yapılır (derlemede `--dart-define=STORE=` ile seçilir):
/// - `github` (varsayılan): GitHub Releases'taki son APK uygulama içinde indirilir, Android kurulum ekranı açılır.
/// - `play`: Google Play'in uygulama içi güncelleme sistemi kullanılır (Play kuralları APK indirmeyi yasaklar).
/// Karşılaştırma derleme numarasıyla yapılır (yayın etiketi v1.0.N = versionCode N + 1).
class UpdateChecker {
  static const store = String.fromEnvironment('STORE', defaultValue: 'github');
  static bool get isPlay => store == 'play';

  static const _latestApi =
      'https://api.github.com/repos/bilkil53/aile-ile-namaz-/releases/latest';
  static const downloadUrl =
      'https://github.com/bilkil53/aile-ile-namaz-/releases/latest/download/aile-ile-namaz.apk';

  static bool _checked = false;

  /// Desteklenen en düşük derleme numarası (docs/app.json → GitHub Pages). Bundan eski sürümde
  /// güncelleme penceresi "Sonra" seçeneği olmadan gösterilir. Okunamazsa 0 (zorlama yok):
  /// internet yokken uygulama kilitlenmez.
  static const _configUrl = 'https://bilkil53.github.io/aile-ile-namaz-/app.json';

  @visibleForTesting
  static int parseMinBuild(String body) {
    try {
      final v = (jsonDecode(body) as Map<String, dynamic>)['min_build'];
      return v is int && v > 0 ? v : 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<int> _minBuild() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse(_configUrl));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return 0;
      return parseMinBuild(await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8)));
    } catch (_) {
      return 0;
    } finally {
      client.close();
    }
  }

  /// Bu telefonun işlemci türüne ait APK adresi (arm64-v8a / armeabi-v7a / x86_64).
  static String? _abiUrl() {
    final abi = switch (Abi.current()) {
      Abi.androidArm64 => 'arm64-v8a',
      Abi.androidArm => 'armeabi-v7a',
      Abi.androidX64 => 'x86_64',
      _ => null,
    };
    return abi == null
        ? null
        : 'https://github.com/bilkil53/aile-ile-namaz-/releases/latest/download/aile-ile-namaz-$abi.apk';
  }

  /// GitHub'daki son sürüm: (numara, açıklamanın ilk satırı). Hata olursa null.
  static Future<(int, String)?> latest() async {
    if (isPlay) {
      final cur = await currentBuild();
      return await _playAvailable() ? (cur + 1, t('Google Play\'de yeni güncelleme var.', 'A new update is available on Google Play.')) : (cur, '');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(_latestApi));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'aile-ile-namaz-app');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15)))
          as Map<String, dynamic>;
      final tag = body['tag_name'] as String? ?? '';
      final n = buildOfTag(tag);
      final notes = ((body['body'] as String?) ?? '').split('\n').first.trim();
      return (n, notes);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// İndirme adresinden GitHub API'deki dosyanın SHA-256 değeri ("digest": "sha256:…"). Yoksa null.
  static Future<String?> _expectedSha256(String url) async {
    final m = RegExp(r'github\.com/([^/]+/[^/]+)/releases/(?:latest/download|download/([^/]+))/([^/?#]+)').firstMatch(url);
    if (m == null) return null;
    final api = m.group(2) == null
        ? 'https://api.github.com/repos/${m.group(1)}/releases/latest'
        : 'https://api.github.com/repos/${m.group(1)}/releases/tags/${m.group(2)}';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(api));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'aile-ile-namaz-app');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null; // 403 (istek sınırı), 404 vb.: doğrulanamaz
      final body = jsonDecode(await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 10)))
          as Map<String, dynamic>;
      for (final a in (body['assets'] as List? ?? const [])) {
        if ((a as Map)['name'] == m.group(3)) {
          final d = a['digest'] as String?;
          return d != null && d.startsWith('sha256:') ? d.substring(7).toLowerCase() : null;
        }
      }
      return null;
    } catch (_) {
      return null; // kontrol yapılamadı: kurulum yapılmaz (fail-closed)
    } finally {
      client.close();
    }
  }

  /// Yüklü derleme numarası. İşlemci türüne göre APK'larda Android sürüm kodu
  /// "tür×1000 + derleme" olur (ör. 3011 = arm64, derleme 11); karşılaştırma derleme numarasıyla yapılır.
  /// Yayın etiketinden derleme numarası: v1.0.0 → 1, v1.0.1-demo → 2, v1.2.57 → 58 (son hane + 1).
  /// Son hane hiç sıfırlanmaz; her yayında bir artar. Eski "r105" biçimli etiketler yok sayılır (0):
  /// v1.0.0 öncesi yayınlar bu uygulamaya güncelleme olarak önerilmez.
  static int buildOfTag(String tag) {
    final m = RegExp(r'^v\d+\.\d+\.(\d+)(-demo)?$').firstMatch(tag.trim());
    if (m == null) return 0;
    final p = int.tryParse(m.group(1)!);
    return p == null ? 0 : p + 1;
  }

  static int buildOf(String buildNumber) => (int.tryParse(buildNumber) ?? 0) % 1000;

  static Future<int> currentBuild() async => buildOf((await PackageInfo.fromPlatform()).buildNumber);

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
      final current = buildOf(info.buildNumber);

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(_latestApi));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'aile-ile-namaz-app');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        client.close();
        return;
      }
      final body = jsonDecode(await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15)))
          as Map<String, dynamic>;
      client.close();

      final tag = body['tag_name'] as String? ?? '';
      final latest = buildOfTag(tag);
      if (latest <= current) return;

      final notes = ((body['body'] as String?) ?? '').split('\n').first.trim();
      // Bu sürüm artık desteklenmiyorsa (ör. gizlilik metni / güvenlik değişikliği) "Sonra" gösterilmez
      final forced = current < await _minBuild();
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: !forced,
        builder: (ctx) => PopScope(
          canPop: !forced,
          child: AlertDialog(
            scrollable: true, // küçük ekran / büyük yazıda taşmasın
            title: Text(forced
                ? t('Güncelleme gerekli', 'Update required')
                : t('Yeni güncelleme var', 'New update available')),
            content: Text(
              (forced
                      ? t('Bu sürüm artık desteklenmiyor. Devam etmek için uygulamayı güncelle.',
                          'This version is no longer supported. Please update the app to continue.')
                      : t('Aile ile Namaz için yeni bir güncelleme hazır.', 'A new update for Aile ile Namaz is ready.')) +
                  (notes.isNotEmpty ? '\n\n$notes' : ''),
            ),
            actions: [
              if (!forced)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(t('Sonra', 'Later')),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('Güncelle', 'Update')),
              ),
            ],
          ),
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
    // İlerleme penceresi geri tuşuyla kapanmaz (PopScope); her yolda yalnızca bir kez, bu fonksiyonla kapatılır.
    // (maybePop bu pencereyi kapatamaz; hata durumunda pencere ekranda asılı kalıyordu.)
    var dialogOpen = true;
    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    // İlerleme penceresi
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(t('Güncelleniyor', 'Updating')),
          content: ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (_, p, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: p),
                const SizedBox(height: 10),
                Text(p == null ? t('İndirme başlıyor…', 'Starting download…') : t('İndiriliyor… %${(p * 100).toStringAsFixed(0)}', 'Downloading… ${(p * 100).toStringAsFixed(0)}%')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                dialogOpen = false;
                Navigator.pop(ctx);
              },
              child: Text(t('Vazgeç', 'Cancel')),
            ),
          ],
        ),
      ),
    ));

    final client = HttpClient();
    var verified = false; // SHA-256 doğrulandı mı
    File? apk; // hata olursa doğrulanmamış (yarım) dosya silinir
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/aile-ile-namaz-$version.apk');
      apk = file;

      // Telefonun işlemci türüne uygun küçük APK (yaklaşık 20 MB); yoksa hepsini içeren APK
      // (Küçük APK'dan büyük APK'ya geçilemez: Android bunu eski sürüm sayar. Bu yüzden yedek yok.)
      final req = await client.getUrl(Uri.parse(_abiUrl() ?? downloadUrl));
      req.headers.set('User-Agent', 'aile-ile-namaz-app');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');

      final total = res.contentLength;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in res) {
          if (cancelled) break;
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) progress.value = received / total;
        }
      } finally {
        await sink.close();
      }
      client.close();
      if (cancelled) {
        if (await file.exists()) await file.delete();
        return;
      }

      // Bütünlük (fail-closed): GitHub'ın yayınladığı SHA-256 alınamazsa ya da uyuşmazsa kurulum yapılmaz,
      // tarayıcıdan indirmeye de düşülmez (doğrulanmamış dosya hiçbir yoldan kurulmasın).
      final expected = await _expectedSha256(_abiUrl() ?? downloadUrl);
      final actual = expected == null ? null : (await sha256.bind(file.openRead()).first).toString();
      if (expected == null || actual != expected) {
        if (await file.exists()) await file.delete();
        closeDialog();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(expected == null
                ? t('Güncelleme doğrulanamadı (bağlantı). Biraz sonra tekrar dene.', 'Could not verify the update (connection). Try again a bit later.')
                : t('İndirilen dosya doğrulanamadı (bozuk ya da değiştirilmiş). Kurulmadı; tekrar dene.', 'The downloaded file could not be verified (corrupt or modified). It was not installed; try again.')),
          ));
        }
        return;
      }
      if (cancelled) {
        // Doğrulama sürerken "Vazgeç"e basıldı: kurulum açılmaz
        if (await file.exists()) await file.delete();
        return;
      }
      verified = true;

      closeDialog();

      // Android'in "Bu uygulamayı güncellemek istiyor musunuz?" ekranı.
      // Önce kendi yöntemimiz: kurulum ayrı görevde açılır, eski pencere kapanır (çift kopya olmaz).
      try {
        final ok = await const MethodChannel('aile/exit').invokeMethod<bool>('installApk', {'path': file.path});
        if (ok == true) return;
      } catch (_) {}
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } catch (e) {
      client.close(force: true);
      Log.warn('guncelleme', e);
      closeDialog();
      if (!verified) {
        try {
          if (apk != null && await apk.exists()) await apk.delete();
        } catch (_) {}
      }
      if (context.mounted && !cancelled) {
        // Tarayıcıdan indirmeye düşülmez: tarayıcının indireceği dosya burada doğrulanmış dosya olmaz.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(verified
              ? t('Kurulum ekranı açılamadı. "Bilinmeyen uygulamaları yükle" iznini verip tekrar dene.', 'Could not open the installer. Allow "Install unknown apps" and try again.')
              : t('Güncelleme indirilemedi. İnternet bağlantını kontrol edip tekrar dene.', 'Could not download the update. Check your internet connection and try again.')),
        ));
      }
    } finally {
      progress.dispose();
    }
  }
}
