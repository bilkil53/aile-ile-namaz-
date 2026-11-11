import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'lang.dart';
import 'theme.dart';

/// Kontrolün sonucu.
enum IntegrityVerdict {
  /// İmza beklenenle aynı.
  ok,

  /// Kontrol yapılmaz: Google Play sürümü (Play kendi anahtarıyla yeniden imzalar; doğrulama Play
  /// Integrity ile yapılmalı) ya da beklenen imza gömülmemiş yerel geliştirme derlemesi.
  skip,

  /// İmza tutmuyor ya da okunamadı: uygulama açılmaz (fail-closed).
  block,
}

/// APK imza kontrolü: uygulama kendi imzasının parmak izini (SHA-256) okur ve derleme sırasında
/// gömülen beklenen değerle karşılaştırır. Başkası APK'yı değiştirip kendi imzasıyla yeniden
/// imzalarsa parmak izi tutmaz ve uygulama AÇILMAZ ("devam et" seçeneği yoktur).
///
/// Not: Bu bir yetki sınırı değildir (değiştirilmiş bir APK bu kontrolü de silebilir); verilere
/// erişim her zaman sunucuda (RLS, RPC) denetlenir. Amaç, değiştirilmiş kopyaların kullanıcıyı
/// kandırmasını zorlaştırmaktır.
class Integrity {
  static const _ch = MethodChannel('aile/exit');

  /// Derlemede --dart-define=EXPECTED_SIG ile gömülür. Birden çok geçerli imza virgülle verilebilir.
  static const _expected = String.fromEnvironment('EXPECTED_SIG');
  static const _store = String.fromEnvironment('STORE', defaultValue: 'github');
  static const _officialUrl = 'https://github.com/bilkil53/aile-ile-namaz-/releases';
  static Future<void>? _run;

  /// Saf karar (birim testleriyle sınanır).
  static IntegrityVerdict verdict({required String? signature, required String expected, required String store}) {
    if (store == 'play') return IntegrityVerdict.skip;
    final valid = expected.toLowerCase().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (valid.isEmpty) return IntegrityVerdict.skip;
    // Telefon imza geçmişindeki bütün sertifikaları virgülle verir; biri tutarsa yeterli
    final got = (signature ?? '').toLowerCase().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (got.isEmpty) return IntegrityVerdict.block; // okunamadı: sessizce geçilmez
    return got.any(valid.contains) ? IntegrityVerdict.ok : IntegrityVerdict.block;
  }

  /// Açılışta bir kez çalışır. İmza tutmazsa ya da okunamazsa kapatılamayan bir pencere gösterir
  /// ve bu fonksiyon geri dönmez (uygulamanın geri kalanı başlamaz).
  /// Engelliyse dönen Future hiç tamamlanmaz: sonradan kurulan başka bir ekran da aynı yerde bekler.
  static Future<void> check(BuildContext context) => _run ??= _check(context);

  static Future<void> _check(BuildContext context) async {
    String? sig;
    try {
      sig = await _ch.invokeMethod<String>('signatureSha256');
    } catch (_) {
      sig = null; // kanal yok / hata: okunamadı sayılır
    }
    if (verdict(signature: sig, expected: _expected, store: _store) != IntegrityVerdict.block) return;
    if (!context.mounted) return Completer<void>().future; // engelli: açılış işleri başlamaz
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          scrollable: true, // küçük ekran / büyük yazıda taşmasın
          icon: const Icon(Icons.gpp_bad_outlined, color: AppColors.missed, size: 34),
          title: Text(t('Bu kopya doğrulanamadı', 'This copy could not be verified')),
          content: Text(
            sig == null || sig.isEmpty
                ? t(
                    'Uygulamanın imzası okunamadığı için güvenliğin adına açılmıyor. '
                        'Lütfen uygulamayı resmi bağlantıdan yeniden kur.',
                    "The app's signature could not be read, so it will not open for your safety. "
                        'Please reinstall the app from the official link.')
                : t(
                    'Bu uygulama resmi kaynaktan kurulmamış ya da üzerinde değişiklik yapılmış. '
                        'Güvenliğin adına açılmıyor. Lütfen resmi sürümü kur.',
                    'This app was not installed from the official source or has been modified. '
                        'It will not open for your safety. Please install the official version.'),
          ),
          actions: [
            TextButton(onPressed: () => SystemNavigator.pop(), child: Text(t('Kapat', 'Close'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
              onPressed: () => launchUrl(Uri.parse(_officialUrl), mode: LaunchMode.externalApplication),
              child: Text(t('Resmi sürümü indir', 'Download the official version')),
            ),
          ],
        ),
      ),
    );
    return Completer<void>().future; // pencere kapanmaz; açılış işleri hiç başlamaz
  }
}
