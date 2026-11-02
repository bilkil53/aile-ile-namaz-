import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'push.dart';
import 'settings.dart';
import 'theme.dart';

/// KVKK açık rızası: veriler hizmetin sunulması için yurt dışındaki sunucularda
/// (Supabase – AB/Frankfurt, Google Firebase) işlenir. Giriş öncesi alınır;
/// rıza tarihi telefonda ve kullanıcının profilinde (kvkk_consent_at) saklanır.
class Kvkk {
  static const _kGiven = 'kvkk.consent';
  static const _kSynced = 'kvkk.synced';
  static const url = 'https://bilkil53.github.io/aile-ile-namaz-/privacy.html#kvkk';

  static const consentText =
      'KVKK Aydınlatma Metni\'ni okudum. Verilerimin uygulamanın çalışması için yurt dışındaki '
      'sunucularda (Supabase – AB/Frankfurt, Google Firebase) işlenmesine ve aktarılmasına açık rıza veriyorum.';

  static bool get given => AppSettings.prefs.getBool(_kGiven) ?? false;

  static Future<void> give() async {
    await AppSettings.prefs.setBool(_kGiven, true);
    await AppSettings.prefs.setBool(_kSynced, false);
  }

  static Future<void> openText() => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  /// Rıza tarihini profile yazar (bir kez).
  static Future<void> syncServer() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || !given || (AppSettings.prefs.getBool(_kSynced) ?? false)) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'kvkk_consent_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', uid)
          .timeout(const Duration(seconds: 8));
      await AppSettings.prefs.setBool(_kSynced, true);
    } catch (_) {}
  }

  /// Giriş yapmış ama henüz rıza vermemiş kullanıcıya bir kez sorulur.
  /// Kabul etmezse oturum kapatılır (gezinti moduyla devam edebilir).
  static Future<void> askIfNeeded(BuildContext context) async {
    if (given) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.verified_user_outlined, color: AppColors.emerald, size: 30),
          title: const Text('Kişisel verilerin korunması (KVKK)'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(consentText),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: openText,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Aydınlatma metnini oku'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kabul etmiyorum')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kabul ediyorum')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await give();
      await syncServer();
    } else {
      await Push.unregister();
      await Supabase.instance.client.auth.signOut();
    }
  }
}
