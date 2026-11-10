import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'lang.dart';
import 'push.dart';
import 'settings.dart';
import 'theme.dart';

/// KVKK aydınlatma: giriş öncesi Aydınlatma Metni'nin okunduğu beyanı alınır (açık rıza DEĞİL).
/// Kurul'un 2026/347 sayılı İlke Kararı: işleme açık rıza dışındaki bir sebebe (sözleşmenin ifası,
/// meşru menfaat) dayanıyorsa ayrıca rıza istenmez, aydınlatma için yalnızca "okudum" beyanı alınır.
/// Beyan tarihi telefonda ve kullanıcının profilinde (kvkk_consent_at alanı) saklanır.
class Kvkk {
  // Beyan HESAP başına tutulur: aynı telefonda ikinci bir hesap açılınca ona da sorulur.
  static const _kUsers = 'kvkk.users'; // "okudum" beyanı vermiş hesaplar (bu telefonda)
  // Giriş ekranında verildi, hesap henüz belli değil. Yalnızca bellekte: giriş iptal olursa ya da
  // uygulama kapanırsa kalmaz, bir sonraki (belki başka kişinin) girişine geçmez.
  static bool _pending = false;
  static String _kSynced(String uid) => 'kvkk.synced.$uid';
  static const _kLegacyGiven = 'kvkk.consent', _kLegacySynced = 'kvkk.synced';
  /// Gizlilik / aydınlatma sayfası, uygulama dilinde
  static String get url => Lang.isEn
      ? 'https://bilkil53.github.io/aile-ile-namaz-/privacy-en.html#kvkk'
      : 'https://bilkil53.github.io/aile-ile-namaz-/privacy.html#kvkk';

  static String get consentText => t('KVKK Aydınlatma Metni\'ni okudum ve anladım.', 'I have read and understood the KVKK Information Notice.');

  static String? get _uid => Supabase.instance.client.auth.currentUser?.id;
  static List<String> get _users => AppSettings.prefs.getStringList(_kUsers) ?? const [];

  /// Bu hesap "okudum" beyanı verdi mi? Giriş yokken: giriş ekranında kutu işaretlendi mi.
  static bool get given {
    final uid = _uid;
    final pending = _pending;
    return uid == null ? pending : (_users.contains(uid) || pending);
  }

  static Future<void> give() async {
    final uid = _uid;
    if (uid == null) {
      _pending = true;
    } else {
      await _addUser(uid);
    }
  }

  static Future<void> _addUser(String uid) async {
    if (!_users.contains(uid)) await AppSettings.prefs.setStringList(_kUsers, [..._users, uid]);
    await AppSettings.prefs.setBool(_kSynced(uid), false);
  }

  /// Girişten sonra çağrılır: giriş ekranında verilen beyanı (ya da eski sürümün telefon başına
  /// kaydını, bir kez) bu hesaba bağlar.
  static Future<void> attach() async {
    final uid = _uid;
    if (uid == null) return;
    final p = AppSettings.prefs;
    final legacy = p.getBool(_kLegacyGiven) ?? false;
    if (_pending || legacy) {
      await _addUser(uid);
      if (legacy && (p.getBool(_kLegacySynced) ?? false)) await p.setBool(_kSynced(uid), true);
      _pending = false;
      await p.remove('kvkk.pending'); // önceki derlemede diske yazılmış olabilir
      await p.remove(_kLegacyGiven);
      await p.remove(_kLegacySynced);
    }
  }

  static Future<void> openText() => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  /// Beyan tarihini profile yazar (hesap başına bir kez; alan adı kvkk_consent_at).
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

  /// Giriş yapmış ama henüz "okudum" beyanı vermemiş kullanıcıya bir kez sorulur.
  /// Vazgeçerse oturum kapatılır (gezinti moduyla devam edebilir).
  static Future<void> askIfNeeded(BuildContext context) async {
    if (given) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.verified_user_outlined, color: AppColors.emerald, size: 30),
          title: Text(t('Kişisel verilerin korunması (KVKK)', 'Protection of personal data (KVKK)')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('Uygulamayı kullanmadan önce, kişisel verilerinizin nasıl işlendiğini anlatan Aydınlatma Metni\'ni okuyun.',
                'Before using the app, please read the Information Notice explaining how your personal data are processed.')),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: openText,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(t('Aydınlatma metnini oku', 'Read the information notice')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Okudum, devam et', 'I have read it, continue'))),
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
