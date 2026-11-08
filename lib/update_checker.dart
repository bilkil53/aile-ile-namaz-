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

import 'log.dart';

/// Güncelleme iki kanaldan yapılır (derlemede `--dart-define=STORE=` ile seçilir):
/// - `github` (varsayılan): GitHub Releases'taki son APK uygulama içinde indirilir, Android kurulum ekranı açılır.
/// - `play`: Google Play'in uygulama içi güncelleme sistemi kullanılır (Play kuralları APK indirmeyi yasaklar).
/// Karşılaştırma derleme numarasıyla yapılır (yayın etiketi rN = versionCode N).
class UpdateChecker {
  static const store = String.fromEnvironment('STORE', defaultValue: 'github');
  static bool get isPlay => store == 'play';

  /// Kanal (`--dart-define=CHANNEL=`): `stable` (varsayılan, ailenin uygulaması) ya da `demo`
  /// (Pro/Demo test uygulaması). Demo sürümleri GitHub'da "ön sürüm" olarak yayınlanır;
  /// stabil uygulama yalnızca normal son sürüme baktığı için demo'yu hiç görmez.
  static const channel = String.fromEnvironment('CHANNEL', defaultValue: 'stable');
  static bool get isDemo => channel == 'demo';

  static const _repo = 'https://github.com/bilkil53/aile-ile-namaz-';
  static const _api = 'https://api.github.com/repos/bilkil53/aile-ile-namaz-/releases';

  /// Demo'da indirilecek yayının etiketi (rN); son sürüm sorgusunda bulunur.
  static String _demoTag = '';

  static String get _base => isDemo ? '$_repo/releases/download/$_demoTag' : '$_repo/releases/latest/download';
  static String get _prefix => isDemo ? 'aile-ile-namaz-demo' : 'aile-ile-namaz';
  static String get downloadUrl => '$_base/$_prefix.apk';

  static bool _checked = false;

  /// Bu telefonun işlemci türüne ait APK adresi (arm64-v8a / armeabi-v7a / x86_64).
  static String? _abiUrl() {
    final abi = switch (Abi.current()) {
      Abi.androidArm64 => 'arm64-v8a',
      Abi.androidArm => 'armeabi-v7a',
      Abi.androidX64 => 'x86_64',
      _ => null,
    };
    return abi == null ? null : '$_base/$_prefix-$abi.apk';
  }

  /// Kanalın son yayını (GitHub API gövdesi). Stabil: /releases/latest. Demo: en yeni "demo" ön sürümü.
  static Future<Map<String, dynamic>?> _fetchLatest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(isDemo ? '$_api?per_page=30' : '$_api/latest'));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'aile-ile-namaz-app');
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final data = jsonDecode(await res.transform(utf8.decoder).join());
      Map<String, dynamic>? body;
      if (isDemo) {
        for (final r in (data as List).cast<Map<String, dynamic>>()) {
          final name = (r['name'] as String? ?? '').toLowerCase();
          if (r['prerelease'] == true && name.contains('demo')) {
            body = r;
            break;
          }
        }
        if (body != null) _demoTag = body['tag_name'] as String? ?? '';
      } else {
        body = data as Map<String, dynamic>;
      }
      return body;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// GitHub'daki son sürüm: (numara, açıklamanın ilk satırı). Hata olursa null.
  static Future<(int, String)?> latest() async {
    if (isPlay) {
      final cur = await currentBuild();
      return await _playAvailable() ? (cur + 1, 'Google Play\'de yeni güncelleme var.') : (cur, '');
    }
    final body = await _fetchLatest();
    if (body == null) return null;
    final tag = body['tag_name'] as String? ?? '';
    final n = int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final notes = ((body['body'] as String?) ?? '').split('\n').first.trim();
    return (n, notes);
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

      final body = await _fetchLatest();
      if (body == null) return;

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
                dialogOpen = false;
                Navigator.pop(ctx);
              },
              child: const Text('Vazgeç'),
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
      final res = await req.close();
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
                ? 'Güncelleme doğrulanamadı (bağlantı). Biraz sonra tekrar dene.'
                : 'İndirilen dosya doğrulanamadı (bozuk ya da değiştirilmiş). Kurulmadı; tekrar dene.'),
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
              ? 'Kurulum ekranı açılamadı. "Bilinmeyen uygulamaları yükle" iznini verip tekrar dene.'
              : 'Güncelleme indirilemedi. İnternet bağlantını kontrol edip tekrar dene.'),
        ));
      }
    } finally {
      progress.dispose();
    }
  }
}
