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
import 'lang.dart';
import 'privacy.dart';
import 'ui_test_mode.dart';

/// Hata bildirimi — HİÇBİR ŞEY OTOMATİK GÖNDERİLMEZ:
/// 1) Uygulama içinde beklenmedik hata olursa kullanıcıya sebebiyle birlikte pencere çıkar.
/// 2) Uygulama ekrandayken tamamen kapanırsa (bellek doldu, çöktü, dondu) Android 11+ sebebi kaydeder;
///    bir sonraki açılışta pencere ile gösterilir.
/// Pencerede kişi isterse "Raporu gönder" (anonim kayıt Supabase `crash_reports` tablosuna) ya da
/// "Mail ile gönder" der; "Kapat" derse hiçbir şey gitmez. Pencere çıkmayan durumlarda (internet
/// kesintisi, arka plandayken kapanma) da hiçbir şey gönderilmez.
/// Gönderilecek metin önce e-posta, oturum anahtarı, kimlik, telefon, gizli parametre, veritabanı satır
/// değerleri ve dosya yollarından temizlenir (privacy.dart).
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
      // kapatırken / arka plandayken olan kapanmalarda pencere çıkmaz, hiçbir şey gönderilmez.
      final foreground = importance <= 200;
      final info = _exitInfo(reason, foreground: foreground);
      if (info == null) return; // normal kapanış (kullanıcı kapattı, güncelleme…)
      if (!foreground) return; // arka plandayken kapanma: pencere yok, rapor da gönderilmez
      final detail = 'Kapanma kodu: $reason (${info.$1})\nBellek: $rssMb MB\n${desc.isEmpty ? '' : 'Android: $desc\n'}'
          '${trace.isEmpty ? '' : '\n${trace.length > 1200 ? trace.substring(0, 1200) : trace}'}';
      _show(
        title: t('Uygulama son kullanımda kapandı', 'The app closed during last use'),
        reason: info.$2,
        detail: detail,
        send: () => _send('EXIT ${info.$1}: $desc (importance $importance, ekrandaydı)', null,
            fatal: true, ramMb: rssMb, rawStack: trace),
      );
    } catch (_) {}
  }

  /// Android kapanma kodu → (kısa ad, kullanıcıya gösterilecek sebep). Normal kapanışta null.
  static (String, String)? _exitInfo(int r, {required bool foreground}) {
    switch (r) {
      case 3:
        // Arka planda bellek için kapatılması Android'in normal davranışıdır; yalnızca ekrandayken göster.
        return foreground
            ? ('LOW_MEMORY', t('Telefonun belleği (RAM) doldu, Android uygulamayı kapattı. Arkada açık uygulamaları kapatmak yardımcı olur.', 'The phone ran out of memory (RAM) and Android closed the app. Closing background apps helps.'))
            : null;
      case 4:
        return ('CRASH', t('Uygulamada bir kod hatası oluştu ve uygulama çöktü.', 'A code error occurred and the app crashed.'));
      case 5:
        return ('CRASH_NATIVE', t('Uygulamanın telefon tarafındaki bir bileşeni çöktü (kod hatası).', 'A native component of the app crashed (code error).'));
      case 6:
        return ('ANR', t('Uygulama dondu ve yanıt vermedi (işlemci yoğunluğu ya da takılan bir işlem).', 'The app froze and stopped responding (high CPU load or a stuck task).'));
      case 7:
        return ('INIT_FAIL', t('Uygulama açılırken başlatılamadı.', 'The app could not start while opening.'));
      case 9:
        return ('EXCESSIVE_RESOURCE', t('Uygulama çok fazla işlemci/pil kullandığı için Android tarafından durduruldu.', 'Android stopped the app because it used too much CPU/battery.'));
      default:
        return null;
    }
  }

  static void _handle(Object error, StackTrace? stack, {required bool fatal}) {
    final text = error.toString();
    final key = text.length > 120 ? text.substring(0, 120) : text;
    if (!_seen.add(key)) return; // aynı hata bir kez
    final ram = (ProcessInfo.currentRss / (1024 * 1024)).round();
    final reason = _reasonOf(error, ram);
    if (reason == null) return; // pencere yok → rapor da yok
    var st = stack?.toString() ?? '';
    if (st.length > 1200) st = st.substring(0, 1200);
    _show(
      title: t('Bir hata oluştu', 'An error occurred'),
      reason: reason,
      detail: 'Hata: ${text.length > 600 ? text.substring(0, 600) : text}\nBellek: $ram MB\n\n$st',
      send: () => _send(text, stack, fatal: fatal, ramMb: ram),
    );
  }

  /// Kullanıcıya anlaşılır sebep. İnternet kesintisi gibi zararsız durumlarda popup açılmaz (null).
  static String? _reasonOf(Object e, int ramMb) {
    final msg = e.toString();
    if (e is SocketException || e is TimeoutException || e is HttpException ||
        msg.contains('SocketException') || msg.contains('Failed host lookup') || msg.contains('ClientException')) {
      return null; // internet yok: uygulama zaten çevrimdışı çalışıyor
    }
    if (msg.contains('OutOfMemory') || ramMb > 700) {
      return t('Uygulama çok fazla bellek (RAM) kullanıyor ($ramMb MB). Telefon belleği yetersiz kalmış olabilir.', 'The app is using too much memory (RAM) ($ramMb MB). The phone may be low on memory.');
    }
    return t(
        'Uygulamanın kodunda bir hata oluştu. Uygulama çalışmaya devam ediyor; '
            'aynı sorun tekrarlarsa geliştiriciye bildirmen düzeltmemize yardımcı olur.',
        'An error occurred in the app code. The app keeps running; '
            'if the same problem happens again, reporting it to the developer helps us fix it.');
  }

  static void _show({
    required String title,
    required String reason,
    required String detail,
    required Future<bool> Function() send,
  }) {
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
            Text(t('Sebep', 'Reason'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(reason),
            const SizedBox(height: 10),
            Text(
                t('Hiçbir bilgi otomatik gönderilmedi. İstersen hata raporunu geliştiriciye gönderebilirsin; '
                        'adın, e-postan ve kayıtların raporda yer almaz.',
                    'Nothing was sent automatically. If you like, you can send the error report to the developer; '
                        'your name, email and records are not included.'),
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
          actionsOverflowButtonSpacing: 4,
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(t('Kapat', 'Close'))),
            TextButton.icon(
              icon: const Icon(Icons.mail_outline, size: 18),
              label: Text(t('Mail ile', 'By email')),
              onPressed: () {
                Navigator.pop(c);
                _mail(title, reason, detail);
              },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.send_outlined, size: 18),
              label: Text(t('Raporu gönder', 'Send report')),
              onPressed: () async {
                Navigator.pop(c);
                final ok = await send();
                final m = navigatorKey.currentContext;
                if (m != null && m.mounted) {
                  ScaffoldMessenger.maybeOf(m)?.showSnackBar(SnackBar(
                      content: Text(ok
                          ? t('Rapor gönderildi, teşekkürler 🤲', 'Report sent, thank you 🤲')
                          : t('Rapor gönderilemedi. İnternetini kontrol et ya da "Mail ile" seçeneğini dene.',
                              'Could not send the report. Check your internet or try "By email".'))));
                }
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
    var body = t('Merhaba,\n\nUygulamada sorun yaşadım. (Ne yaparken olduğunu buraya yazabilirsin)\n\n\n',
            'Hello,\n\nI had a problem with the app. (You can write what you were doing here)\n\n\n') +
        '---\n$title\nSebep: $reason\nSürüm: v$_version (iç derleme $_build)\nCihaz: $os\n\n${scrubSensitive(detail)}';
    if (body.length > 1800) body = body.substring(0, 1800);
    final q = {
      'subject': t('Aile ile Namaz – Hata bildirimi (v$_version)', 'Aile ile Namaz – Error report (v$_version)'),
      'body': body,
    }.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');
    try {
      await launchUrl(Uri(scheme: 'mailto', path: AppConfig.supportEmail, query: q),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Yalnızca kişi "Raporu gönder"e basınca çağrılır. Gittiyse true.
  static Future<bool> _send(String text, StackTrace? stack, {required bool fatal, int? ramMb, String? rawStack}) async {
    try {
      if (_sentThisRun >= 5 || kUiTest) return false; // CI ekran testindeki hatalar canlı tabloya gitmesin
      _sentThisRun++;
      var st = scrubSensitive(rawStack ?? stack?.toString() ?? '');
      if (st.length > 7500) st = st.substring(0, 7500);
      final err = scrubSensitive(text);
      var os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      if (os.length > 190) os = os.substring(0, 190);
      await Supabase.instance.client.from('crash_reports').insert({
        'app_version': _version,
        'build': _build,
        'os': os,
        'ram_mb': ramMb ?? (ProcessInfo.currentRss / (1024 * 1024)).round(),
        'fatal': fatal,
        'error': err.length > 1900 ? err.substring(0, 1900) : err,
        'stack': st,
      }).timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false; // internet yok / sunucu hatası: kişiye söylenir, "Mail ile" önerilir
    }
  }
}
