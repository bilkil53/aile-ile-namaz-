import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';

/// Hata bildirimi:
/// 1) Uygulama içinde beklenmedik hata olursa kullanıcıya sebebiyle birlikte popup çıkar,
///    "Geliştiriciye mail gönder" ile ayrıntılar hazır mail olarak açılır.
/// 2) Uygulama tamamen kapanırsa (bellek doldu, çöktü, dondu) Android 11+ sebebi kaydeder;
///    bir sonraki açılışta popup ile gösterilir.
/// 3) Her iki durumda da anonim kayıt Supabase `crash_reports` tablosuna gider.
/// Kişisel veri (ad, e-posta, namaz kaydı) gönderilmez.
class CrashReport {
  static final navigatorKey = GlobalKey<NavigatorState>();
  static const _ch = MethodChannel('aile/exit');
  static const _kLastExit = 'crash.lastExitTime';

  static String _version = '';
  static int _build = 0;
  static int _sentThisRun = 0;
  static int _shownThisRun = 0;
  static DateTime? _lastShown;
  static bool _dialogOpen = false;
  static final Set<String> _seen = {};

  static Future<void> install() async {
    try {
      final i = await PackageInfo.fromPlatform();
      _version = i.version;
      _build = (int.tryParse(i.buildNumber) ?? 0) % 1000;
    } catch (_) {}
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      prev?.call(details);
      _handle(details.exception, details.stack, fatal: false);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      _handle(error, stack, fatal: true);
      return true;
    };
  }

  /// Açılışta çağrılır: önceki oturum anormal kapandıysa sebebini gösterir.
  static Future<void> checkLastExit() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('lastExit');
      if (m == null) return;
      final time = (m['time'] as num?)?.toInt() ?? 0;
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getInt(_kLastExit);
      await prefs.setInt(_kLastExit, time);
      final hasTrace = ((m['trace'] as String?) ?? '').isNotEmpty;
      if (!hasTrace && (seen == null || time <= seen)) return; // ilk kurulum ya da zaten gösterildi
      final reason = (m['reason'] as num?)?.toInt() ?? 0;
      final importance = (m['importance'] as num?)?.toInt() ?? 1000;
      final rssMb = (((m['rssKb'] as num?)?.toInt() ?? 0) / 1024).round();
      final desc = (m['desc'] as String?) ?? '';
      final trace = (m['trace'] as String?) ?? '';
      // Ekrandayken mi kapandı? (100 = ön planda, 200 = görünür). Kullanıcı uygulamayı
      // kapatırken / arka plandayken olan kapanmalar sadece sessizce raporlanır, popup çıkmaz.
      final foreground = importance <= 200;
      final info = _exitInfo(reason, foreground: foreground);
      if (info == null) return; // normal kapanış (kullanıcı kapattı, güncelleme…)
      unawaited(_send('EXIT ${info.$1}: $desc (importance $importance${foreground ? ', ekrandaydı' : ', arka plandaydı'})',
          null, fatal: true, ramMb: rssMb, rawStack: trace));
      if (!foreground) return;
      final detail = 'Kapanma kodu: $reason (${info.$1})\nBellek: $rssMb MB\n${desc.isEmpty ? '' : 'Android: $desc\n'}'
          '${trace.isEmpty ? '' : '\n${trace.length > 1200 ? trace.substring(0, 1200) : trace}'}';
      _show(
        title: 'Uygulama son kullanımda kapandı',
        reason: info.$2,
        detail: detail,
      );
    } catch (_) {}
  }

  /// Android kapanma kodu → (kısa ad, kullanıcıya gösterilecek sebep). Normal kapanışta null.
  static (String, String)? _exitInfo(int r, {required bool foreground}) {
    switch (r) {
      case 3:
        // Arka planda bellek için kapatılması Android'in normal davranışıdır; yalnızca ekrandayken göster.
        return foreground
            ? ('LOW_MEMORY', 'Telefonun belleği (RAM) doldu, Android uygulamayı kapattı. Arkada açık uygulamaları kapatmak yardımcı olur.')
            : null;
      case 4:
        return ('CRASH', 'Uygulamada bir kod hatası oluştu ve uygulama çöktü.');
      case 5:
        return ('CRASH_NATIVE', 'Uygulamanın telefon tarafındaki bir bileşeni çöktü (kod hatası).');
      case 6:
        return ('ANR', 'Uygulama dondu ve yanıt vermedi (işlemci yoğunluğu ya da takılan bir işlem).');
      case 7:
        return ('INIT_FAIL', 'Uygulama açılırken başlatılamadı.');
      case 9:
        return ('EXCESSIVE_RESOURCE', 'Uygulama çok fazla işlemci/pil kullandığı için Android tarafından durduruldu.');
      default:
        return null;
    }
  }

  static void _handle(Object error, StackTrace? stack, {required bool fatal}) {
    final text = error.toString();
    final key = text.length > 120 ? text.substring(0, 120) : text;
    if (!_seen.add(key)) return; // aynı hata bir kez
    final ram = (ProcessInfo.currentRss / (1024 * 1024)).round();
    unawaited(_send(text, stack, fatal: fatal, ramMb: ram));
    final reason = _reasonOf(error, ram);
    if (reason == null) return;
    var st = stack?.toString() ?? '';
    if (st.length > 1200) st = st.substring(0, 1200);
    _show(
      title: 'Bir hata oluştu',
      reason: reason,
      detail: 'Hata: ${text.length > 600 ? text.substring(0, 600) : text}\nBellek: $ram MB\n\n$st',
    );
  }

  /// Kullanıcıya anlaşılır sebep. İnternet kesintisi gibi zararsız durumlarda popup açılmaz (null).
  static String? _reasonOf(Object e, int ramMb) {
    final t = e.toString();
    if (e is SocketException || e is TimeoutException || e is HttpException ||
        t.contains('SocketException') || t.contains('Failed host lookup') || t.contains('ClientException')) {
      return null; // internet yok: uygulama zaten çevrimdışı çalışıyor
    }
    if (t.contains('OutOfMemory') || ramMb > 700) {
      return 'Uygulama çok fazla bellek (RAM) kullanıyor ($ramMb MB). Telefon belleği yetersiz kalmış olabilir.';
    }
    return 'Uygulamanın kodunda bir hata oluştu. Uygulama çalışmaya devam ediyor; '
        'aynı sorun tekrarlarsa geliştiriciye bildirmen düzeltmemize yardımcı olur.';
  }

  static void _show({required String title, required String reason, required String detail}) {
    // Spam olmasın: bir açılışta en fazla 2 popup, aralarında en az 30 sn
    if (_dialogOpen || _shownThisRun >= 2) return;
    if (_lastShown != null && DateTime.now().difference(_lastShown!) < const Duration(seconds: 30)) return;
    void open([int tries = 0]) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) {
        if (tries < 20) Future.delayed(const Duration(milliseconds: 500), () => open(tries + 1));
        return;
      }
      _dialogOpen = true;
      _shownThisRun++;
      _lastShown = DateTime.now();
      showDialog<void>(
        context: ctx,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
          title: Text(title, textAlign: TextAlign.center),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sebep', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(reason),
            const SizedBox(height: 10),
            const Text('Hata kaydı otomatik ve anonim olarak geliştiriciye iletildi. '
                'İstersen ayrıntıları mail ile de gönderebilirsin.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat')),
            FilledButton.icon(
              icon: const Icon(Icons.mail_outline, size: 18),
              label: const Text('Mail gönder'),
              onPressed: () {
                Navigator.pop(c);
                _mail(title, reason, detail);
              },
            ),
          ],
        ),
      ).whenComplete(() => _dialogOpen = false);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => open());
  }

  static Future<void> _mail(String title, String reason, String detail) async {
    final os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    var body = 'Merhaba,\n\nUygulamada sorun yaşadım. (Ne yaparken olduğunu buraya yazabilirsin)\n\n\n'
        '---\n$title\nSebep: $reason\nSürüm: v$_version (iç derleme $_build)\nCihaz: $os\n\n$detail';
    if (body.length > 1800) body = body.substring(0, 1800);
    final q = {
      'subject': 'Aile ile Namaz – Hata bildirimi (v$_version)',
      'body': body,
    }.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
    try {
      await launchUrl(Uri(scheme: 'mailto', path: AppConfig.supportEmail, query: q),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  static Future<void> _send(String text, StackTrace? stack, {required bool fatal, int? ramMb, String? rawStack}) async {
    try {
      if (_sentThisRun >= 5) return;
      _sentThisRun++;
      var st = rawStack ?? stack?.toString() ?? '';
      if (st.length > 7500) st = st.substring(0, 7500);
      var os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      if (os.length > 190) os = os.substring(0, 190);
      await Supabase.instance.client.from('crash_reports').insert({
        'app_version': _version,
        'build': _build,
        'os': os,
        'ram_mb': ramMb ?? (ProcessInfo.currentRss / (1024 * 1024)).round(),
        'fatal': fatal,
        'error': text.length > 1900 ? text.substring(0, 1900) : text,
        'stack': st,
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // İnternet yoksa sessizce geç
    }
  }
}
