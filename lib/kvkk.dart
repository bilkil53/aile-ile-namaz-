import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'push.dart';
import 'settings.dart';
import 'theme.dart';

/// KVKK açık rızası: veriler hizmetin sunulması için yurt dışındaki sunucularda
/// (Supabase – AB/Frankfurt, Google Firebase) işlenir. Giriş öncesi alınır;
/// rıza tarihi telefonda ve kullanıcının profilinde (kvkk_consent_at) saklanır.
class Kvkk {
  // Rıza HESAP başına tutulur: aynı telefonda ikinci bir hesap açılınca ona da sorulur.
  static const _kUsers = 'kvkk.users'; // rıza vermiş hesaplar (bu telefonda)
  static const _kPending = 'kvkk.pending'; // giriş ekranında verildi, hesap henüz belli değil
  static String _kSynced(String uid) => 'kvkk.synced.$uid';
  static const _kLegacyGiven = 'kvkk.consent', _kLegacySynced = 'kvkk.synced';
  static const url = 'https://bilkil53.github.io/aile-ile-namaz-/privacy.html#kvkk';

  static const consentText =
      'KVKK Aydınlatma Metni\'ni okudum. Verilerimin uygulamanın çalışması için yurt dışındaki '
      'sunucularda (Supabase – AB/Frankfurt, Google Firebase) işlenmesine ve aktarılmasına açık rıza veriyorum.';

  static String? get _uid => Supabase.instance.client.auth.currentUser?.id;
  static List<String> get _users => AppSettings.prefs.getStringList(_kUsers) ?? const [];

  /// Bu hesap rıza verdi mi? Giriş yokken: giriş ekranında kutu işaretlendi mi.
  static bool get given {
    final uid = _uid;
    final pending = AppSettings.prefs.getBool(_kPending) ?? false;
    return uid == null ? pending : (_users.contains(uid) || pending);
  }

  static Future<void> give() async {
    final uid = _uid;
    if (uid == null) {
      await AppSettings.prefs.setBool(_kPending, true);
    } else {
      await _addUser(uid);
    }
  }

  static Future<void> _addUser(String uid) async {
    if (!_users.contains(uid)) await AppSettings.prefs.setStringList(_kUsers, [..._users, uid]);
    await AppSettings.prefs.setBool(_kSynced(uid), false);
  }

  /// Girişten sonra çağrılır: giriş ekranında verilen rızayı (ya da eski sürümün telefon başına
  /// rızasını, bir kez) bu hesaba bağlar.
  static Future<void> attach() async {
    final uid = _uid;
    if (uid == null) return;
    final p = AppSettings.prefs;
    final legacy = p.getBool(_kLegacyGiven) ?? false;
    if ((p.getBool(_kPending) ?? false) || legacy) {
      await _addUser(uid);
      if (legacy && (p.getBool(_kLegacySynced) ?? false)) await p.setBool(_kSynced(uid), true);
      await p.remove(_kPending);
      await p.remove(_kLegacyGiven);
      await p.remove(_kLegacySynced);
    }
  }

  static Future<void> openText() => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  /// Rıza tarihini profile yazar (hesap başına bir kez).
  static Future<void> syncServer() async {
    final uid = _uid;
    if (uid == null || !_users.contains(uid) || (AppSettings.prefs.getBool(_kSynced(uid)) ?? false)) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'kvkk_consent_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', uid)
          .timeout(const Duration(seconds: 8));
      await AppSettings.prefs.setBool(_kSynced(uid), true);
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
      await Repo.signOut();
    }
  }
}
