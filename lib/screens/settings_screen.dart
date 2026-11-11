import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../config.dart';
import '../lang.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../data_export.dart';
import '../local_store.dart';
import '../log.dart';
import '../location.dart';
import '../notifications.dart';
import '../push.dart';
import '../settings.dart';
import '../theme.dart';
import '../update_checker.dart';
import 'notify_health_screen.dart';

/// Ayarlar.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _repo = 'https://github.com/bilkil53/aile-ile-namaz-';

  String _version = '';
  int _build = 0;
  int? _latest;
  String _notes = '';
  bool _checking = false;
  bool _syncing = false;
  bool _gpsBusy = false;
  bool _exact = true;

  /// Bekleyen kayıt sayısı değişince senkron satırı yenilenir (açıkken de güncel kalsın).
  void _queueRebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LocalStore.queueChanged.removeListener(_queueRebuild);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    LocalStore.queueChanged.addListener(_queueRebuild);
    Notifications.exactAllowed().then((v) {
      if (mounted) setState(() => _exact = v);
    });
    PackageInfo.fromPlatform().then((i) {
      if (!mounted) return;
      setState(() {
        _version = i.version;
        _build = UpdateChecker.buildOf(i.buildNumber);
      });
    });
  }

  static String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    return d == null ? '' : DateFormat('d MMMM yyyy', Lang.code).format(d);
  }

  /// Önbelleği temizle: telefondaki vakit önbelleği ve aile özeti silinir.
  /// Namaz kayıtların, bekleyen gönderimler ve bulut verin silinmez.
  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true, // küçük ekran / büyük yazıda taşmasın
        title: Text(t('Önbelleği temizle', 'Clear cache'), style: TextStyle(fontSize: 17)),
        content: Text(t(
            'Telefonda saklanan namaz vakitleri ve aile havuzu özeti silinir, internetten yeniden alınır.\n\n'
                'Namaz kayıtların, kaza sayıların ve buluttaki verilerin silinmez.',
            'Prayer times and the family summary stored on the phone are deleted and reloaded from the internet.\n\n'
                'Your prayer records, kaza counts and cloud data are not deleted.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Temizle', 'Clear'))),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = AppSettings.prefs;
    var n = 0;
    for (final k in prefs.getKeys().toList()) {
      if (k.startsWith('pt_') || k == 'familySnapshot' || k.startsWith('diniGunler')) {
        await prefs.remove(k);
        n++;
      }
    }
    unawaited(Notifications.reschedule());
    _toast(n == 0 ? t('Önbellek zaten temiz ✓', 'Cache is already clean ✓') : t('Önbellek temizlendi ✓ ($n kayıt)', 'Cache cleared ✓ ($n items)'));
  }

  /// Anlık bildirim hatası: ayrıntı + kopyala + tekrar dene (destek için).
  Future<void> _pushProblem() async {
    final detail = Push.lastErrorDetail.isEmpty ? Push.status.value : Push.lastErrorDetail;
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Anlık bildirim hatası', 'Push notification error'), style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(detail.length > 3000 ? detail.substring(0, 3000) : detail,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: detail));
              if (ctx.mounted) Navigator.pop(ctx, false);
              _toast(t('Hata ayrıntısı kopyalandı. Geliştiriciye gönderebilirsin.', 'Error details copied. You can send them to the developer.'));
            },
            child: Text(t('Kopyala', 'Copy')),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Tekrar dene', 'Try again'))),
        ],
      ),
    );
    if (again == true) await Push.register();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  /// Öneri & Destek: telefondaki mail uygulamasını hazır konu ve sürüm bilgisiyle açar.
  Future<void> _mail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConfig.supportEmail,
      query: _enc({
        'subject': t('Aile ile Namaz – Öneri / Destek (v$_version)', 'Aile ile Namaz – Feedback / Support (v$_version)'),
        'body': t('Merhaba,\n\n\n\n---\nSürüm: v$_version (iç derleme $_build)',
            'Hello,\n\n\n\n---\nVersion: v$_version (build $_build)'),
      }),
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _toast(t('Telefonda mail uygulaması bulunamadı.', 'No email app found on the phone.'));
  }

  static String _enc(Map<String, String> q) =>
      q.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&');

  Future<void> _check() async {
    setState(() => _checking = true);
    final r = await UpdateChecker.latest();
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (r != null) {
        _latest = r.$1;
        _notes = r.$2;
      }
    });
    if (r == null) {
      _toast(t('Sürüm bilgisi alınamadı. İnternet bağlantını kontrol et.', 'Could not get version info. Check your internet connection.'));
    } else if (r.$1 <= _build) {
      _toast(t('Uygulaman güncel ✓', 'Your app is up to date ✓'));
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final sent = await Repo.syncNowCount();
    if (!mounted) return;
    setState(() => _syncing = false);
    final left = LocalStore.pendingCount;
    _toast(left == 0
        ? (sent > 0 ? t('$sent işaretin gönderildi ✓', '$sent marks sent ✓') : t('Tüm işaretlerin zaten kaydedildi ✓', 'All your marks are already saved ✓'))
        : t('$left işaretin henüz gönderilemedi. İnternet gelince kendiliğinden gider.', '$left marks not sent yet. They will be sent automatically when online.'));
  }

  Future<void> _gps() async {
    setState(() => _gpsBusy = true);
    final (ok, msg) = await LocationHelper.updateFromGps();
    if (!mounted) return;
    setState(() => _gpsBusy = false);
    _toast(ok ? t('Konum güncellendi: $msg', 'Location updated: $msg') : msg);
    if (ok) {
      await Notifications.reschedule();
    }
  }

  bool _exporting = false;

  /// Sunucudaki kendi kayıtlarını dosya olarak hazırlar ve paylaşım ekranını açar (kaydet / e-posta / Drive).
  Future<void> _exportData() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final (File, List<String>) res;
      try {
        res = await DataExport.create(appVersion: _version);
      } catch (e) {
        Log.warn('verilerimi indir', e);
        if (mounted) {
          _toast(t('Veriler hazırlanamadı. İnternet bağlantını kontrol edip tekrar dene.',
              'Could not prepare your data. Check your internet connection and try again.'));
        }
        return;
      }
      final (file, missing) = res;
      if (!mounted) return;
      if (missing.isNotEmpty) {
        _toast(t('Bazı bölümler okunamadı, dosyada eksik olarak belirtildi. Sonra tekrar dene.',
            'Some sections could not be read and are marked as missing in the file. Try again later.'));
      }
      try {
        await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')],
            subject: t('Aile İle Namaz — verilerim', 'Aile İle Namaz — my data'));
      } catch (e) {
        Log.warn('verilerimi indir (paylaşım)', e);
        if (mounted) _toast(t('Paylaşım ekranı açılamadı. Tekrar dene.', 'Could not open the share screen. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _deleteAccount() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true, // küçük ekran / büyük yazıda taşmasın
        title: Text(t('Hesabımı ve verilerimi sil', 'Delete my account and data')),
        content: Text(t(
          'Namaz kayıtların, kaza sayıların ve havuz üyeliklerin kalıcı olarak silinir. '
              'Reisi olduğun ve başka üyesi olan havuzların reisliği en eski üyeye geçer. Bu işlem geri alınamaz.',
          'Your prayer records, kaza counts and family circle memberships are permanently deleted. '
              'For circles you lead that have other members, leadership passes to the oldest member. This cannot be undone.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.missed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Devam', 'Continue')),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t('Son kez soruyoruz: hesabın ve tüm verilerin silinsin mi?', 'Last chance: delete your account and all your data?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Hayır', 'No'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.missed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('Evet, sil', 'Yes, delete')),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await Repo.deleteMyAccount();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on PostgrestException catch (e) {
      // Sunucu isteği aldı ama silme tamamlanamadı: bağlantı sorunu gibi gösterilmez
      Log.warn('hesap silme', e);
      _toast(t('Sunucuda bir hata oluştu, hesabın silinmedi. Biraz sonra tekrar dene; sürerse "Hesap silme" sayfasındaki e-posta adresine yaz.',
          'A server error occurred and your account was not deleted. Try again later; if it continues, email the address on the "Delete account" page.'));
    } catch (e) {
      Log.warn('hesap silme', e);
      _toast(t('Silinemedi. İnternet bağlantını kontrol edip tekrar dene.', 'Could not delete. Check your internet connection and try again.'));
    }
  }

  /// Çıkış: önce bekleyen kayıtlar gönderilmeye çalışılır; hâlâ gönderilmemiş kayıt varsa uyarılır
  /// (çıkışta bu hesabın telefondaki verisi silinir, başka hesaba geçmez).
  Future<void> _signOut() async {
    try {
      await Repo.syncNow().timeout(const Duration(seconds: 10));
    } catch (_) {}
    final left = LocalStore.pendingCount;
    if (left > 0 && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true, // küçük ekran / büyük yazıda taşmasın
          title: Text(t('Gönderilmemiş kayıt var', 'Unsent records')),
          content: Text(t(
              '$left kayıt henüz buluta gönderilemedi (internet yok olabilir).\n\n'
                  'Çıkış yaparsan bu kayıtlar kaybolmaz: bu telefonda senin adına saklanır '
                  '(${LocalStore.parkDays} gün), aynı hesapla tekrar giriş yapınca otomatik gönderilir. '
                  'Bu telefonda başka biri giriş yaparsa senin kayıtlarını göremez.',
              '$left records have not been sent to the cloud yet (maybe no internet).\n\n'
                  'If you sign out they are not lost: they are kept on this phone for you '
                  '(${LocalStore.parkDays} days) and sent automatically when you sign in again with the same account. '
                  'Anyone else signing in on this phone cannot see your records.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Vazgeç', 'Cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.missed),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Çıkış yap', 'Sign out')),
            ),
          ],
        ),
      );
      if (go != true) return;
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await Push.unregister();
    await Repo.signOut();
  }

  // ---------- Arayüz parçaları ----------

  Widget _bigCard(List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        decoration: BoxDecoration(
          color: AppColors.emerald,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _divider() => Divider(color: Colors.white.withValues(alpha: 0.18), height: 18);

  Widget _whiteBtn(String label, VoidCallback? onTap, {IconData? icon}) => FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.emerald,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onPressed: onTap,
        icon: Icon(icon ?? Icons.arrow_forward, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _outlineBtn(String label, VoidCallback? onTap, {IconData? icon}) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        onPressed: onTap,
        icon: Icon(icon ?? Icons.refresh, size: 18),
        label: Text(label),
      );

  Widget _subSwitch(String title, bool value, String key) => Padding(
        padding: const EdgeInsets.only(left: 14),
        child: Row(children: [
          Icon(Icons.subdirectory_arrow_right, size: 16, color: Colors.white.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12, color: Colors.white))),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: value,
              activeThumbColor: AppColors.emerald,
              activeTrackColor: AppColors.prayedMint,
              onChanged: (v) async {
                await AppSettings.setNotify(key, v);
                setState(() {});
                unawaited(Push.register()); // tercih sunucudaki cihaz kaydına da yazılır
              },
            ),
          ),
        ]),
      );

  Widget _switchRow(String title, String sub, bool value, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
              Text(sub, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
            ]),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.emerald,
            activeTrackColor: AppColors.prayedMint,
          ),
        ]),
      );

  /// Sürüm satırına dokununca: son sürümün açıklaması (uygulama içinde).
  Future<void> _showNotes() async {
    if (_notes.isEmpty) {
      final r = await UpdateChecker.latest();
      if (r != null && mounted) setState(() { _latest = r.$1; _notes = r.$2; });
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Sürüm v$_version', 'Version v$_version'), style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(_notes.isEmpty ? t('Sürüm açıklaması alınamadı. İnternet bağlantını kontrol et.', 'Could not load release notes. Check your internet connection.') : _notes,
                style: const TextStyle(fontSize: 12, height: 1.4)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => _open('$_repo/releases/latest'), child: Text(t('GitHub\'da aç', 'Open on GitHub'))),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Tamam', 'OK'))),
        ],
      ),
    );
  }

  /// Dil seçimi: telefonun diline göre / Türkçe / English. Seçince ekranlar hemen yeni dille çizilir.
  Future<void> _pickLang() async {
    final cur = Lang.choice;
    final picked = await showDialog<AppLang>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t('Uygulama dili', 'App language'), style: const TextStyle(fontSize: 17)),
        children: [
          for (final l in AppLang.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, l),
              child: Row(children: [
                Icon(l == cur ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: AppColors.emerald, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(Lang.label(l), style: const TextStyle(fontSize: 15))),
              ]),
            ),
        ],
      ),
    );
    if (picked == null || picked == cur) return;
    await Lang.set(picked);
    // Planlanmış hatırlatmalar yeni dille yeniden kurulur; aile bildirimleri için cihaz dili sunucuya yazılır
    unawaited(Notifications.reschedule());
    unawaited(Push.register());
    if (mounted) setState(() {});
  }

  /// "Verilerin" kutusu: hangi veri nerede (bulut / telefon), en son ne zaman gönderildi, bekleyen var mı.
  Widget _dataBox(String email) {
    final white70 = Colors.white.withValues(alpha: 0.75);
    // Yeni işaretler 20 sn bekleyip gönderilir: bunlar "birazdan gönderilecek", gerçekten
    // bekleyenler (internet yok, gönderilemedi) "telefonda bekliyor" sayılır.
    final soon = Repo.scheduledPrayers();
    final pPrayer = LocalStore.pendingOf('prayer') - soon, pKaza = LocalStore.pendingOf('kaza');
    final pending = pPrayer + pKaza;
    String when(DateTime? d) {
      if (d == null) return t('henüz gönderim yok', 'nothing sent yet');
      final now = DateTime.now();
      // Takvim günü farkı UTC üzerinden: yaz saati geçişinde 23/25 saatlik gün yanlış sonuç vermez
      final days = DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
      final hm = DateFormat('HH:mm').format(d);
      if (days == 0) return t('bugün $hm', 'today $hm');
      if (days == 1) return t('dün $hm', 'yesterday $hm');
      return '${DateFormat('d MMMM', Lang.code).format(d)} $hm';
    }

    String state(int n, [int soonN = 0]) => n > 0
        ? t('$n kayıt telefonda bekliyor', '$n waiting on the phone')
        : soonN > 0
            ? t('Birazdan gönderilecek', 'Sending shortly')
            : t('Bulutta ✓', 'In the cloud ✓');
    Widget row(IconData icon, String label, String value, {String? sub, bool warn = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: white70)),
              ]),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: warn ? AppColors.goldContainer : AppColors.prayedMint)),
            ),
          ]),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.cloud_outlined, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(t('Verilerin', 'Your data'),
                style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          if (_syncing)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        ]),
        Divider(color: Colors.white.withValues(alpha: 0.18), height: 14),
        row(Icons.mosque_outlined, t('Namaz işaretleri', 'Prayer marks'), state(pPrayer, soon),
            sub: t('Son gönderim: ', 'Last sent: ') + when(LocalStore.lastSynced('prayer')), warn: pPrayer > 0),
        row(Icons.calendar_month_outlined, t('Kaza kayıtları', 'Kaza records'), state(pKaza),
            sub: t('Son gönderim: ', 'Last sent: ') + when(LocalStore.lastSynced('kaza')), warn: pKaza > 0),
        row(Icons.phone_android, t('Telefonda bekleyen', 'Waiting on the phone'),
            pending == 0 ? t('Yok', 'None') : t('$pending kayıt', '$pending records'),
            sub: pending == 0 ? null : t('İnternet gelince kendiliğinden gönderilir', 'Sent automatically when online'),
            warn: pending > 0),
        Divider(color: Colors.white.withValues(alpha: 0.18), height: 14),
        if (email.trim().isNotEmpty)
          Text(
              t('Kayıtların $email hesabına bağlı; telefon değişse de kaybolmaz.',
                  'Your records are linked to $email; they are not lost if you change phones.'),
              style: TextStyle(fontSize: 11, color: white70)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _syncing ? null : _sync,
            icon: const Icon(Icons.sync, size: 16, color: Colors.white),
            label: Text(_syncing ? t('Gönderiliyor…', 'Sending…') : t('Şimdi eşitle', 'Sync now'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }

  Widget _title(String t) => Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white));

  Widget _tapRow(String label, IconData icon, VoidCallback onTap, {String? sub, Widget? trailing, Color? color}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 20, color: color ?? Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 14, color: color ?? Colors.white, fontWeight: FontWeight.w600)),
                if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
              ]),
            ),
            trailing ?? Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.7)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final guest = isGuest;
    final hasUpdate = _latest != null && _latest! > _build;
    final user = supa.auth.currentUser;
    final name = (user?.userMetadata?['full_name'] ?? user?.userMetadata?['name'] ?? '') as String;
    final email = user?.email ?? '';
    final syncText = t('Gezinti modu · kayıt yapılmaz', 'Browsing mode · nothing is saved');
    return Scaffold(
      appBar: AppBar(title: Text(t('Ayarlar', 'Settings'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      // Alt gezinme çubuğu / hareket çizgisi olan telefonlarda son öğe çubuğun altında kalmasın
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1) Uygulama
            _bigCard([
              _title(t('Uygulama', 'App')),
              _divider(),
              Row(children: [
                const Icon(Icons.location_on, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(AppSettings.cityName,
                        style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
                    Text(
                      LocationHelper.permissionDenied
                          ? t('Konum izni yok — İstanbul vakitleri gösteriliyor', 'No location permission — showing Istanbul times')
                          : t('GPS ile otomatik · sadece telefonda tutulur', 'Automatic via GPS · stored only on the phone'),
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
                    ),
                  ]),
                ),
                TextButton(
                  onPressed: _gpsBusy
                      ? null
                      : (LocationHelper.permissionDenied ? LocationHelper.openSettings : _gps),
                  child: Text(LocationHelper.permissionDenied ? t('İzin ver', 'Allow') : (_gpsBusy ? '…' : t('Yenile', 'Refresh')),
                      style: const TextStyle(color: AppColors.prayedMint, fontWeight: FontWeight.bold)),
                ),
              ]),
              _divider(),
              _tapRow(t('Dil', 'Language'), Icons.translate, _pickLang, sub: Lang.label(Lang.choice)),
              _divider(),
              InkWell(
                onTap: _showNotes,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    const Icon(Icons.info_outline, size: 20, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t('Sürüm v$_version', 'Version v$_version'),
                            style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
                        Text(t('Sürüm notları için dokun', 'Tap for release notes'),
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
                      ]),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: hasUpdate ? AppColors.goldContainer : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: hasUpdate ? AppColors.gold : AppColors.prayedMint),
                      ),
                      child: Text(hasUpdate ? t('Güncelleme var!', 'Update available!') : t('✓ Güncel', '✓ Up to date'),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: hasUpdate ? const Color(0xFF78350F) : AppColors.prayedMint)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              if (hasUpdate)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.goldContainer, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('Yeni Güncelleme Hazır 🎉', 'New Update Ready 🎉'),
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF78350F))),
                    if (_notes.isNotEmpty)
                      Text(_notes, maxLines: 6, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF78350F))),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
                      onPressed: () => UpdateChecker.install(context, _latest!),
                      icon: const Icon(Icons.system_update, size: 18),
                      label: Text(t('Hemen Güncelle', 'Update Now')),
                    ),
                  ]),
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: _outlineBtn(_checking ? t('Sorgulanıyor…', 'Checking…') : t('Güncellemeleri Kontrol Et', 'Check for Updates'), _checking ? null : _check),
                ),
              _divider(),
              _tapRow(t('Önbelleği temizle', 'Clear cache'), Icons.cleaning_services_outlined, _clearCache,
                  sub: t('Vakitler ve aile özeti yeniden alınır · kayıtların silinmez', 'Prayer times and family summary are reloaded · your records are kept')),
              const SizedBox(height: 6),
            ]),
            const SizedBox(height: 14),
            // 2) Hesap
            _bigCard([
              _title(t('Hesap', 'Account')),
              _divider(),
              Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  child: Icon(guest ? Icons.person_outline : Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(guest ? t('Gezinti modu', 'Browsing mode') : (name.isEmpty ? t('Google hesabı', 'Google account') : name),
                        style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
                    if (!guest && email.isNotEmpty)
                      Text(email, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
                    if (!guest && _fmtDate(user?.createdAt).isNotEmpty)
                      Text(
                          t('Üyelik: ${_fmtDate(user?.createdAt)}', 'Member since: ${_fmtDate(user?.createdAt)}') +
                              (_fmtDate(user?.lastSignInAt).isEmpty
                                  ? ''
                                  : t(' · Son giriş: ${_fmtDate(user?.lastSignInAt)}',
                                      ' · Last sign-in: ${_fmtDate(user?.lastSignInAt)}')),
                          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
                  ]),
                ),
              ]),
              const SizedBox(height: 10),
              if (guest)
                Text(syncText, style: const TextStyle(fontSize: 13, color: AppColors.prayedMint, fontWeight: FontWeight.w600))
              else
                _dataBox(email),
              const SizedBox(height: 6),
              if (guest)
                _whiteBtn(t('Google ile Giriş Yap', 'Sign in with Google'), () async {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  await LocalStore.setGuestMode(false);
                }, icon: Icons.login)
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: _outlineBtn(t('Çıkış Yap', 'Sign Out'), _signOut, icon: Icons.logout),
                ),
              const SizedBox(height: 6),
            ]),
            // 3) Verilerimi indir + hesabı sil
            if (!guest) ...[
              const SizedBox(height: 18),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _exporting ? null : _exportData,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Icon(Icons.download, color: AppColors.textSecondary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t('Verilerimi indir', 'Download my data'),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          Text(t('Namaz kayıtların, kaza sayıların ve aile üyeliklerin tek dosyada', 'Your prayer records, kaza counts and memberships in one file'),
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ]),
                      ),
                      _exporting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.missed.withValues(alpha: 0.5)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _deleteAccount,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      const Icon(Icons.delete_forever, color: AppColors.missed, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(t('Hesabımı ve verilerimi sil', 'Delete my account and data'),
                              style: TextStyle(fontSize: 14, color: AppColors.missed, fontWeight: FontWeight.bold)),
                          Text(t('Tüm kayıtların kalıcı olarak silinir', 'All your records are permanently deleted'),
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ]),
                      ),
                      Icon(Icons.chevron_right, color: AppColors.missed.withValues(alpha: 0.7)),
                    ]),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            // 4) Bildirimler
            _bigCard([
              _title(t('Bildirimler', 'Notifications')),
              _divider(),
              _tapRow(t('Bildirim izinlerini kontrol et', 'Check notification permissions'), Icons.health_and_safety_outlined,
                  () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotifyHealthScreen())),
                  sub: t('İzin, kesin alarm, pil tasarrufu · test bildirimi', 'Permission, exact alarms, battery saver · test notification'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white)),
              if (AppSettings.prayerReminders && !_exact)
                InkWell(
                  onTap: () async {
                    await Notifications.requestExact();
                    final v = await Notifications.exactAllowed();
                    if (mounted) setState(() => _exact = v);
                    unawaited(Notifications.reschedule());
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.goldContainer, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(Icons.alarm, color: Color(0xFF78350F), size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(t('Hatırlatmalar birkaç dakika gecikebilir. Tam zamanında gelmesi için "Alarm ve hatırlatıcılar" iznini ver.', 'Reminders may be a few minutes late. Allow "Alarms & reminders" for on-time reminders.'),
                            style: TextStyle(fontSize: 12, color: Color(0xFF78350F))),
                      ),
                      Text(t('İzin ver', 'Allow'), style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.emerald)),
                    ]),
                  ),
                ),
              _switchRow(t('Aile bildirimleri', 'Family notifications'), t('Aileden biri namaz kılınca / dua gönderince', 'When a family member prays / sends a dua'), AppSettings.familyAlerts,
                  (v) async {
                await AppSettings.setFamilyAlerts(v);
                await Push.register();
                setState(() {});
              }),
              if (AppSettings.familyAlerts) ...[
                _subSwitch(t('Namaz kıldı bildirimleri', 'Prayer notifications'), AppSettings.notifyPrayer, 'notifyPrayer'),
                _subSwitch(t('Kaza namazı bildirimleri', 'Kaza prayer notifications'), AppSettings.notifyKaza, 'notifyKaza'),
                _subSwitch(t('Dua bildirimleri', 'Dua notifications'), AppSettings.notifyDua, 'notifyDua'),
                _subSwitch(t('Kilit ekranında içeriği göster', 'Show content on lock screen'), AppSettings.lockScreen, 'lockScreen'),
              ],
              // Anlık bildirim satırı yalnızca sorun varsa görünür
              if (!guest)
                ValueListenableBuilder<String>(
                  valueListenable: Push.status,
                  builder: (_, s, __) => Push.ok
                      ? const SizedBox.shrink()
                      : InkWell(
                          onTap: _pushProblem,
                          child: Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.missedCoral.withValues(alpha: 0.6)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.notifications_off, size: 18, color: AppColors.missedCoral),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(t('Uygulama kapalıyken aile bildirimleri gelmeyebilir: $s · tekrar denemek için dokun', 'Family notifications may not arrive while the app is closed: $s · tap to retry'),
                                    style: const TextStyle(fontSize: 12, color: Colors.white)),
                              ),
                            ]),
                          ),
                        ),
                ),
              const SizedBox(height: 6),
            ]),
            const SizedBox(height: 14),
            // 5) Diğer
            _bigCard([
              _title(t('Diğer', 'Other')),
              _divider(),
              _tapRow(t('Uygulamayı paylaş', 'Share the app'), Icons.share, () async {
                // Telefonun paylaşım penceresi: WhatsApp, Gmail, Mesajlar, Telegram…
                await Share.share(
                  t('🕌 Aile ile Namaz — ailenle birlikte namaz takibi, kaza takibi ve aile havuzu.\n\n'
                      'Android için indir: $_repo/releases/latest/download/aile-ile-namaz.apk',
                    '🕌 Aile ile Namaz — prayer tracking, kaza tracking and a family circle, together with your family.\n\n'
                      'Download for Android: $_repo/releases/latest/download/aile-ile-namaz.apk'),
                  subject: t('Aile ile Namaz uygulaması', 'Aile ile Namaz app'),
                );
              }),
              _tapRow(t('Öneri yaz', 'Send feedback'), Icons.mail_outline, _mail, sub: t('Mail uygulaması açılır', 'Opens your email app')),
              _tapRow('GitHub', Icons.star_rounded, () => _open(_repo),
                  sub: t('Kaynak kod · Yıldız ver ⭐', 'Source code · Give a star ⭐'),
                  trailing: const Icon(Icons.open_in_new, color: Colors.white, size: 18)),
              _tapRow(t('Gizlilik politikası', 'Privacy policy'), Icons.privacy_tip_outlined,
                  () => _open(t('https://bilkil53.github.io/aile-ile-namaz-/privacy.html',
                      'https://bilkil53.github.io/aile-ile-namaz-/privacy-en.html')),
                  trailing: const Icon(Icons.open_in_new, color: Colors.white, size: 18)),
              const SizedBox(height: 6),
            ]),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
