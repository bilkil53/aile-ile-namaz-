import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'lang.dart';
import 'push.dart';
import 'settings.dart';
import 'theme.dart';

/// KVKK: giriş öncesi İKİ AYRI beyan alınır (Kurul'un 2026/347 sayılı İlke Kararı: aydınlatma ve
/// açık rıza ayrı metinlerle, ayrı onaylarla alınır):
///  1) Aydınlatma Metni'nin okunduğu beyanı ("okudum ve anladım") — rıza DEĞİL; tarih: kvkk_consent_at.
///  2) Açık rıza — namaz/kaza kayıtları ve dua mesajları dini inancı ortaya koyabildiği için özel
///     nitelikli kişisel veridir (Kanun md. 6/3-a); tarih: acik_riza_at (yalnızca sunucu saatiyle yazılır).
/// İkisi de verilmeden giriş yapılamaz.
class Kvkk {
  // Beyanlar HESAP başına tutulur: aynı telefonda ikinci bir hesap açılınca ona da sorulur.
  static const _kUsers = 'kvkk.users'; // "okudum" beyanı vermiş hesaplar (bu telefonda)
  static const _kRizaUsers = 'riza.users'; // açık rıza vermiş hesaplar (bu telefonda)
  // Giriş ekranında verildi, hesap henüz belli değil. Yalnızca bellekte: giriş iptal olursa ya da
  // uygulama kapanırsa kalmaz, bir sonraki (belki başka kişinin) girişine geçmez.
  static bool _pending = false;
  static String _kSynced(String uid) => 'kvkk.synced.$uid';
  static String _kRizaSynced(String uid) => 'riza.synced.$uid';
  // Bu hesabın onayladığı açık rıza metninin sürümü (eski kayıtlarda yok → 1. sürüm)
  static String _kRizaVer(String uid) => 'riza.version.$uid';

  /// Bu uygulamanın gösterdiği Açık Rıza Metni sürümü. Metin değişince birlikte artırılır
  /// (sunucuda private.riza_version() de aynı anda yükseltilir).
  static const rizaTextVersion = 1;

  /// Sunucunun istediği metin sürümü (son kontrolde öğrenilen). Bu uygulamanınkinden yeniyse
  /// pencere rıza almak yerine "uygulamayı güncelleyin" der: eski metne verilen rıza geçersizdir.
  static int _requiredVersion = 0;
  static const _kLegacyGiven = 'kvkk.consent', _kLegacySynced = 'kvkk.synced';
  static String get _page => Lang.isEn
      ? 'https://bilkil53.github.io/aile-ile-namaz-/privacy-en.html'
      : 'https://bilkil53.github.io/aile-ile-namaz-/privacy.html';
  /// Gizlilik / aydınlatma sayfası, uygulama dilinde
  static String get url => '$_page#kvkk';
  /// Açık Rıza Metni (aynı sayfada ayrı bölüm), uygulama dilinde
  static String get rizaUrl => '$_page#acik-riza';

  static String get consentText => t('KVKK Aydınlatma Metni\'ni okudum ve anladım.', 'I have read and understood the KVKK Information Notice.');
  static String get rizaText => t(
      'Açık Rıza Metni\'ni okudum; namaz ve kaza kayıtlarımın, dua ve tebrik mesajlarımın işlenmesine ve aile havuzumdaki kişilere gösterilmesine açık rıza veriyorum.',
      'I have read the Explicit Consent Text; I give my explicit consent for my prayer and kaza records and my dua and greeting messages to be processed and shown to the people in my family circle.');

  static String? get _uid => Supabase.instance.client.auth.currentUser?.id;
  static List<String> get _users => AppSettings.prefs.getStringList(_kUsers) ?? const [];
  static List<String> get _rizaUsers => AppSettings.prefs.getStringList(_kRizaUsers) ?? const [];

  /// Bu hesap iki beyanı da verdi mi? Giriş yokken: giriş ekranında iki kutu da işaretlendi mi.
  static bool get given {
    final uid = _uid;
    final pending = _pending;
    return uid == null ? pending : ((_users.contains(uid) && _rizaUsers.contains(uid)) || pending);
  }

  /// Bu hesap yalnızca eski "okudum" beyanını vermiş (açık rıza henüz yok) → "metin güncellendi" denir.
  static bool get _onlyAck {
    final uid = _uid;
    return uid != null && _users.contains(uid) && !_rizaUsers.contains(uid);
  }

  /// Giriş yapılmadan vazgeçildiyse giriş ekranında verilen beyanlar unutulur.
  static void clearPending() => _pending = false;

  /// İki beyan birlikte verilir (iki kutu da işaretlenmeden çağrılmaz).
  static Future<void> give() async {
    final uid = _uid;
    if (uid == null) {
      _pending = true;
    } else {
      await _addUser(uid);
    }
  }

  static Future<void> _addUser(String uid) async {
    final p = AppSettings.prefs;
    if (!_users.contains(uid)) {
      await p.setStringList(_kUsers, [..._users, uid]);
      await p.setBool(_kSynced(uid), false);
    }
    if (!_rizaUsers.contains(uid)) {
      await p.setStringList(_kRizaUsers, [..._rizaUsers, uid]);
      await p.setBool(_kRizaSynced(uid), false);
      await p.setInt(_kRizaVer(uid), rizaTextVersion);
    }
  }

  static int _localVersion(String uid) => AppSettings.prefs.getInt(_kRizaVer(uid)) ?? 1;

  /// Girişten sonra çağrılır: giriş ekranında verilen beyanları bu hesaba bağlar. Eski sürümün telefon
  /// başına kaydı yalnızca "okudum" beyanı olarak taşınır; açık rıza yeniden sorulur.
  static Future<void> attach() async {
    final uid = _uid;
    if (uid == null) return;
    final p = AppSettings.prefs;
    final legacy = p.getBool(_kLegacyGiven) ?? false;
    if (_pending) {
      await _addUser(uid);
      _pending = false;
    } else if (legacy && !_users.contains(uid)) {
      await p.setStringList(_kUsers, [..._users, uid]);
      await p.setBool(_kSynced(uid), p.getBool(_kLegacySynced) ?? false);
    }
    if (legacy) {
      await p.remove(_kLegacyGiven);
      await p.remove(_kLegacySynced);
    }
    await p.remove('kvkk.pending'); // önceki derlemede diske yazılmış olabilir
  }

  static Future<void> openText() => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  static Future<void> openRiza() => launchUrl(Uri.parse(rizaUrl), mode: LaunchMode.externalApplication);

  /// Beyan ve rıza tarihlerini profile yazar (hesap başına bir kez). Açık rıza tarihi sunucu saatiyle
  /// yazılır (record_acik_riza); başarısız olursa bir sonraki açılışta yeniden denenir.
  static Future<void> syncServer() async {
    final uid = _uid;
    if (uid == null) return;
    final p = AppSettings.prefs;
    final db = Supabase.instance.client;
    if (_users.contains(uid) && !(p.getBool(_kSynced(uid)) ?? false)) {
      try {
        final ack = await db
            .from('profiles')
            .update({'kvkk_consent_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', uid)
            .select('id')
            .timeout(const Duration(seconds: 8));
        // Satır güncellenmediyse (profil yok) yazılmadı say, sonra yeniden dene
        if (ack.isNotEmpty && _uid == uid) await p.setBool(_kSynced(uid), true);
      } catch (_) {}
    }
    if (_rizaUsers.contains(uid) && !(p.getBool(_kRizaSynced(uid)) ?? false)) {
      try {
        // Okunan metnin sürümü gönderilir: sunucuda metin bu arada yenilendiyse kayıt yazılmaz
        final at = await db
            .rpc('record_acik_riza', params: {'p_version': _localVersion(uid)})
            .timeout(const Duration(seconds: 8));
        // Profil satırı yoksa ya da metin eskimişse tarih dönmez → yazılmadı say
        if (at != null && _uid == uid) await p.setBool(_kRizaSynced(uid), true);
      } catch (_) {}
    }
  }

  /// Sunucudaki kayıt ile telefondaki kaydı karşılaştırır (sunucu esastır).
  static ConsentAction decide({
    required bool serverBeyan,
    required bool serverRiza,
    required bool localGiven,
    required bool localSynced,
    int localVersion = 1,
    int requiredVersion = 1,
  }) {
    if (serverBeyan && serverRiza) return ConsentAction.adopt; // başka telefonda verilmiş de olabilir
    // Verilmiş ama henüz yazılamamış: yalnızca okunan metin hâlâ güncelse yeniden gönderilir
    if (localGiven && !localSynced && localVersion >= requiredVersion) return ConsentAction.resend;
    return ConsentAction.ask; // sunucuda geçerli rıza yok (hiç verilmemiş ya da metin sürümü eski)
  }

  /// Her açılışta ve öne gelişte çağrılır: sunucuda geçerli (güncel sürümlü) açık rıza yoksa `true`
  /// döner → pencere yeniden sorulur. Sunucuda varsa bu telefonda da tanınır (yeni telefonda tekrar
  /// sorulmaz). İnternet yoksa `false` (engellemez; bir sonraki açılışta yeniden bakılır).
  static Future<bool> needsServerConsent() async {
    final uid = _uid;
    if (uid == null) return false;
    final p = AppSettings.prefs;
    try {
      for (var round = 0; round < 2; round++) {
        final j = await Supabase.instance.client.rpc('my_consent_status').timeout(const Duration(seconds: 6));
        if (j is! Map || _uid != uid) return false;
        // Profil satırı yoksa kayıt yazılamaz: sormak sonsuz pencereye döner, bu durumda engellenmez
        if (j['profil'] == false) return false;
        final reqVer = (j['gerekli_version'] as num?)?.toInt() ?? 1;
        _requiredVersion = reqVer;
        final localGiven = _users.contains(uid) && _rizaUsers.contains(uid);
        final localSynced = (p.getBool(_kSynced(uid)) ?? false) && (p.getBool(_kRizaSynced(uid)) ?? false);
        switch (decide(
          serverBeyan: j['beyan'] == true,
          serverRiza: j['riza'] == true,
          localGiven: localGiven,
          localSynced: localSynced,
          localVersion: _localVersion(uid),
          requiredVersion: reqVer,
        )) {
          case ConsentAction.adopt:
            if (!_users.contains(uid)) await p.setStringList(_kUsers, [..._users, uid]);
            if (!_rizaUsers.contains(uid)) await p.setStringList(_kRizaUsers, [..._rizaUsers, uid]);
            await p.setBool(_kSynced(uid), true);
            await p.setBool(_kRizaSynced(uid), true);
            await p.setInt(_kRizaVer(uid), (j['riza_version'] as num?)?.toInt() ?? reqVer);
            return false;
          case ConsentAction.resend:
            if (round == 1) return false; // yazılamadı (ör. bağlantı): sonraki açılışta yeniden denenir
            await syncServer();
          case ConsentAction.ask:
            // Telefondaki kayıt geçersiz: silinir ki pencere yeniden çıksın
            if (j['beyan'] != true) {
              await p.setStringList(_kUsers, _users.where((u) => u != uid).toList());
              await p.remove(_kSynced(uid));
            }
            await p.setStringList(_kRizaUsers, _rizaUsers.where((u) => u != uid).toList());
            await p.remove(_kRizaSynced(uid));
            await p.remove(_kRizaVer(uid));
            return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Giriş yapmış ama iki beyanı birden vermemiş kullanıcıya bir kez sorulur (ör. açık rıza
  /// eklenmeden önce giriş yapmış olanlar). Vazgeçerse oturum kapatılır (gezinti moduyla devam edebilir).
  static Future<void> askIfNeeded(BuildContext context) async {
    if (given) return;
    if (_requiredVersion > rizaTextVersion) {
      // Sunucudaki metin bu uygulamadakinden yeni: eski metne rıza alınmaz, güncelleme istenir
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            icon: const Icon(Icons.system_update, color: AppColors.emerald, size: 30),
            title: Text(t('Uygulamayı güncelleyin', 'Please update the app')),
            content: Text(t(
                'Gizlilik metinlerimiz güncellendi. Yeni metni okuyup onaylayabilmek için uygulamanın son sürümünü kurun. Şimdilik oturumunuz kapatılır; uygulamayı gezinti modunda görüntüleyebilirsiniz.',
                'Our privacy texts have been updated. Please install the latest version of the app to read and accept the new text. For now you will be signed out; you can still view the app in browsing mode.')),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Tamam', 'OK')))],
          ),
        ),
      );
      await Push.unregister();
      await Repo.signOut();
      return;
    }
    final updated = _onlyAck;
    var ack = false, riza = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
            icon: const Icon(Icons.verified_user_outlined, color: AppColors.emerald, size: 30),
            title: Text(t('Kişisel verilerin korunması (KVKK)', 'Protection of personal data (KVKK)')),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(updated
                    ? t('Gizlilik metnimiz güncellendi. Devam etmek için iki metni de okuyup işaretleyin. Vazgeçerseniz oturumunuz kapatılır; uygulamayı gezinti modunda görüntüleyebilirsiniz.',
                        'Our privacy texts have been updated. To continue, please read and tick both texts. If you cancel, you will be signed out; you can still view the app in browsing mode.')
                    : t('Devam etmek için iki metni de okuyup işaretleyin. Vazgeçerseniz oturumunuz kapatılır; uygulamayı gezinti modunda görüntüleyebilirsiniz.',
                        'To continue, please read and tick both texts. If you cancel, you will be signed out; you can still view the app in browsing mode.')),
                const SizedBox(height: 8),
                ConsentBox(
                  value: ack,
                  text: consentText,
                  link: t('Aydınlatma metnini oku', 'Read the information notice'),
                  onLink: openText,
                  onChanged: (v) => setD(() => ack = v),
                ),
                ConsentBox(
                  value: riza,
                  text: rizaText,
                  link: t('Açık rıza metnini oku', 'Read the explicit consent text'),
                  onLink: openRiza,
                  onChanged: (v) => setD(() => riza = v),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel'))),
              FilledButton(
                  onPressed: ack && riza ? () => Navigator.pop(ctx, true) : null,
                  child: Text(t('Devam et', 'Continue'))),
            ],
          ),
        ),
      ),
    );
    // Pencere açıkken oturum düştüyse beyan kimseye bağlanmaz (sonraki girişe taşınmasın)
    if (ok == true && _uid != null) {
      await give(); // sunucuya yazma home_shell'deki syncServer ile (açılışı bekletmez)
    } else {
      await Push.unregister();
      await Repo.signOut();
    }
  }
}

/// Sunucu–telefon rıza karşılaştırmasının sonucu.
enum ConsentAction { adopt, resend, ask }

/// İşaret kutusu + metin + "oku" bağlantısı (giriş ekranı ve güncelleme penceresi ortak).
class ConsentBox extends StatelessWidget {
  final bool value;
  final bool warn;
  final String text, link;
  final VoidCallback onLink;
  final ValueChanged<bool> onChanged;
  const ConsentBox({
    super.key,
    required this.value,
    required this.text,
    required this.link,
    required this.onLink,
    required this.onChanged,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 32,
        height: 32,
        child: Checkbox(value: value, activeColor: AppColors.emerald, onChanged: (v) => onChanged(v ?? false)),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => onChanged(!value),
            child: Text(text,
                style: TextStyle(fontSize: 11, height: 1.35, color: warn && !value ? AppColors.missed : AppColors.textSecondary)),
          ),
          InkWell(
            onTap: onLink,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(link,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.emerald, decoration: TextDecoration.underline)),
            ),
          ),
        ]),
      ),
    ]);
  }
}
