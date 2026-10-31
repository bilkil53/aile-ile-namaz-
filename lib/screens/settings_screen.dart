import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../local_store.dart';
import '../location.dart';
import '../notifications.dart';
import '../push.dart';
import '../settings.dart';
import '../theme.dart';
import '../update_checker.dart';

/// Ayarlar (eski uygulamadaki "Uygulama Bilgileri" kartı + eklemeler).
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
  String _lastSync = '';
  bool _exact = true;
  String _nextReminder = '';

  @override
  void initState() {
    super.initState();
    Notifications.exactAllowed().then((v) {
      if (mounted) setState(() => _exact = v);
    });
    _loadNextReminder();
    PackageInfo.fromPlatform().then((i) {
      if (!mounted) return;
      setState(() {
        _version = i.version;
        _build = int.tryParse(i.buildNumber) ?? 0;
      });
    });
  }

  Future<void> _loadNextReminder() async {
    try {
      final r = await Notifications.nextReminder();
      if (!mounted) return;
      setState(() => _nextReminder = r == null
          ? ''
          : 'Sıradaki hatırlatma: ${r.$1} ${r.$2.hour.toString().padLeft(2, '0')}:${r.$2.minute.toString().padLeft(2, '0')} (vakit ${r.$3})');
    } catch (_) {}
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
      path: 'e.bilkil5391@gmail.com',
      query: _enc({
        'subject': 'Aile ile Namaz – Öneri / Destek (v$_version)',
        'body': 'Merhaba,\n\n\n\n---\nSürüm: v$_version (iç derleme $_build)',
      }),
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _toast('Telefonda mail uygulaması bulunamadı.');
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
      _toast('Sürüm bilgisi alınamadı. İnternet bağlantını kontrol et.');
    } else if (r.$1 <= _build) {
      _toast('Uygulaman güncel ✓');
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final sent = await Repo.flushQueue();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastSync = TimeOfDay.now().format(context);
    });
    final left = LocalStore.pendingCount;
    _toast(left == 0
        ? (sent > 0 ? '$sent bekleyen kayıt buluta gönderildi ☁️' : 'Tüm kayıtların bulutta ✓')
        : '$left kayıt hâlâ bekliyor. İnternet bağlantını kontrol et.');
  }

  Future<void> _gps() async {
    setState(() => _gpsBusy = true);
    final (ok, msg) = await LocationHelper.updateFromGps();
    if (!mounted) return;
    setState(() => _gpsBusy = false);
    _toast(ok ? 'Konum güncellendi: $msg' : msg);
    if (ok) {
      await Notifications.reschedule();
      unawaited(_loadNextReminder());
    }
  }

  Future<void> _deleteAccount() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hesabımı ve verilerimi sil'),
        content: const Text(
          'Namaz kayıtların, kaza sayıların ve havuz üyeliklerin kalıcı olarak silinir. '
          'Reisi olduğun ve başka üyesi olan havuzların reisliği en eski üyeye geçer. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.missed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Devam'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('Son kez soruyoruz: hesabın ve tüm verilerin silinsin mi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayır')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.missed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, sil'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await Repo.deleteMyAccount();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      _toast('Silinemedi. İnternet bağlantını kontrol edip tekrar dene.');
    }
  }

  // ---------- Arayüz parçaları ----------

  Widget _bigCard(List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        decoration: BoxDecoration(
          color: AppColors.emerald,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _divider() => Divider(color: Colors.white.withValues(alpha: 0.18), height: 22);

  Widget _row(String label, Widget value, {IconData? icon}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 20, color: Colors.white), const SizedBox(width: 10)],
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.88))),
          ),
          value,
        ]),
      );

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
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13, color: Colors.white))),
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
              Text(title, style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600)),
              Text(sub, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
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

  @override
  Widget build(BuildContext context) {
    final guest = isGuest;
    final hasUpdate = _latest != null && _latest! > _build;
    final pending = LocalStore.pendingCount;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ayarlar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Uygulama Bilgileri', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _bigCard([
            Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: const Icon(Icons.info, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Uygulama Bilgileri', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('Aile ile Namaz', style: TextStyle(fontSize: 14, color: Colors.white)),
              ]),
            ]),
            _divider(),
            _row('Uygulama', const Text('Aile ile Namaz',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white))),
            _divider(),
            _row(
              'Sürüm',
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('v$_version', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: hasUpdate ? AppColors.goldContainer : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: hasUpdate ? AppColors.gold : AppColors.prayedMint),
                  ),
                  child: Text(hasUpdate ? 'Güncelleme var!' : '✓ Güncel',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: hasUpdate ? const Color(0xFF78350F) : AppColors.prayedMint)),
                ),
                IconButton(
                  tooltip: 'Sürüm açıklaması',
                  onPressed: () => _open('$_repo/releases/latest'),
                  icon: const Icon(Icons.open_in_new, color: Colors.white, size: 20),
                ),
              ]),
            ),
            if (hasUpdate) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.goldContainer, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Yeni Güncelleme Hazır 🎉',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF78350F))),
                  if (_notes.isNotEmpty)
                    Text(_notes, style: const TextStyle(fontSize: 12, color: Color(0xFF78350F))),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
                    onPressed: () => UpdateChecker.install(context, _latest!),
                    icon: const Icon(Icons.system_update, size: 18),
                    label: const Text('Hemen Güncelle'),
                  ),
                ]),
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: _outlineBtn(_checking ? 'Sorgulanıyor…' : 'Güncellemeleri Kontrol Et', _checking ? null : _check),
              ),
            _divider(),
            _row(
              'Veritabanı Durumu',
              Text(guest ? 'Kaydedilmiyor (Gezinti) 👀' : 'Bulut Senkronize ☁️',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.prayedMint)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(guest ? Icons.phone_android : Icons.cloud_done, color: AppColors.prayedMint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(guest ? 'Gezinti Modu: Kalıcı Kayıt Yok' : 'Hesaba Bağlı Bulut Yedekleme Aktif',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  guest
                      ? 'Giriş yapmadığın için kıldı/kılmadı işaretlerin, kaza sayıların ve Aile Havuzunda denediklerin '
                          'sadece bu oturumda tutuluyor; uygulama kapanınca silinir. Google ile giriş yaparsan bu oturumdakiler buluta kaydedilir.'
                      : 'Kıldı/kılmadı işaretlerin, kaza namazların ve tüm ibadet geçmişin Google hesabına bağlı olarak '
                          'buluta yedekleniyor. Uygulamayı silsen veya telefon değiştirsen bile aynı hesapla giriş yaptığında '
                          'bütün kayıtların geri gelir. İnternet yokken işaretlediklerin telefonda bekler, bağlantı gelince gönderilir.',
                  style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.9), height: 1.4),
                ),
                if (!guest && (pending > 0 || _lastSync.isNotEmpty)) ...[
                  const SizedBox(height: 6),
                  Text(
                    pending > 0 ? '⏳ $pending kayıt gönderilmeyi bekliyor' : 'Son yedekleme: $_lastSync',
                    style: const TextStyle(fontSize: 12, color: AppColors.prayedMint, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 12),
                if (guest)
                  _whiteBtn('Google ile Giriş Yap & Buluta Yedekle', () async {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    await LocalStore.setGuestMode(false);
                  }, icon: Icons.login)
                else
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.22),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _syncing ? null : _sync,
                        icon: const Icon(Icons.sync, size: 18),
                        label: Text(_syncing ? 'Yedekleniyor…' : 'Şimdi Yedekle ☁️'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _outlineBtn('Çıkış Yap', () async {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      await Push.unregister();
                      await supa.auth.signOut();
                    }, icon: Icons.logout),
                  ]),
              ]),
            ),
            _divider(),
            _row('Geliştirici', const Text('bilkil53',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white))),
            _divider(),
            _row(
              'Proje & Kaynak Kod',
              Flexible(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _open('$_repo/releases/latest'),
                  child: const Text('Detaylar & Son Sürüm\nAçıklaması (latest)',
                      textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              icon: Icons.code,
            ),
            _divider(),
            _row('Öneri & Destek', _whiteBtn('Öneri Yaz', _mail, icon: Icons.mail),
                icon: Icons.mail),
            const SizedBox(height: 6),
          ]),
          const SizedBox(height: 14),
          _bigCard([
            const Text('Konum ve Bildirimler',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            _divider(),
            Row(children: [
              const Icon(Icons.location_on, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppSettings.cityName,
                      style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600)),
                  Text(
                    LocationHelper.permissionDenied
                        ? 'Konum izni yok — İstanbul vakitleri gösteriliyor'
                        : 'GPS ile otomatik · sadece telefonda tutulur',
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                  ),
                ]),
              ),
              TextButton(
                onPressed: _gpsBusy
                    ? null
                    : (LocationHelper.permissionDenied ? LocationHelper.openSettings : _gps),
                child: Text(LocationHelper.permissionDenied ? 'İzin ver' : (_gpsBusy ? '…' : 'Yenile'),
                    style: const TextStyle(color: AppColors.prayedMint, fontWeight: FontWeight.bold)),
              ),
            ]),
            _divider(),
            _switchRow('Vakit hatırlatması', 'Her vakitten ${AppSettings.reminderMinutes} dakika önce',
                AppSettings.prayerReminders, (v) async {
              await AppSettings.setPrayerReminders(v);
              if (v) await Notifications.requestPermission();
              unawaited(Notifications.reschedule());
              setState(() {});
              unawaited(_loadNextReminder());
            }),
            if (AppSettings.prayerReminders && _nextReminder.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 6),
                child: Row(children: [
                  const Icon(Icons.alarm, size: 16, color: AppColors.prayedMint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$_nextReminder${_exact ? ' · tam zamanında' : ' · birkaç dk gecikebilir'}',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                  ),
                ]),
              ),
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
                  child: const Row(children: [
                    Icon(Icons.alarm, color: Color(0xFF78350F), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Hatırlatmalar birkaç dakika gecikebilir. Tam zamanında gelmesi için "Alarm ve hatırlatıcılar" iznini ver.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF78350F))),
                    ),
                    Text('İzin ver', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.emerald)),
                  ]),
                ),
              ),
            _switchRow('Günün ayeti / hadisi', 'Her gün 12:00\'de', AppSettings.dailyContent, (v) async {
              await AppSettings.setDailyContent(v);
              if (v) await Notifications.requestPermission();
              unawaited(Notifications.reschedule());
              setState(() {});
            }),
            _switchRow('Aile bildirimleri', 'Aileden biri namaz kılınca / dua gönderince', AppSettings.familyAlerts,
                (v) async {
              await AppSettings.setFamilyAlerts(v);
              await Push.register();
              setState(() {});
            }),
            if (AppSettings.familyAlerts) ...[
              _subSwitch('Namaz kıldı bildirimleri', AppSettings.notifyPrayer, 'notifyPrayer'),
              _subSwitch('Kaza namazı bildirimleri', AppSettings.notifyKaza, 'notifyKaza'),
              _subSwitch('Dua bildirimleri', AppSettings.notifyDua, 'notifyDua'),
              _subSwitch('Kilit ekranında içeriği göster', AppSettings.lockScreen, 'lockScreen'),
            ],
            if (!guest)
              ValueListenableBuilder<String>(
                valueListenable: Push.status,
                builder: (_, s, __) => InkWell(
                  onTap: Push.ok ? null : () => Push.register(),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Row(children: [
                      Icon(Push.ok ? Icons.notifications_active : Icons.notifications_off,
                          size: 16, color: Push.ok ? AppColors.prayedMint : AppColors.missedCoral),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Anlık bildirim: $s${Push.ok ? '' : ' · tekrar denemek için dokun'}',
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
                      ),
                    ]),
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ]),
          const SizedBox(height: 14),
          _bigCard([
            const Text('Diğer', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            _divider(),
            InkWell(
              onTap: () async {
                // Telefonun paylaşım penceresi: WhatsApp, Gmail, Mesajlar, Telegram…
                await Share.share(
                  '🕌 Aile ile Namaz — ailenle birlikte namaz takibi, kaza takibi ve aile havuzu.\n\n'
                  'Android için indir: $_repo/releases/latest/download/aile-ile-namaz.apk',
                  subject: 'Aile ile Namaz uygulaması',
                );
              },
              child: _row('Uygulamayı paylaş', const Icon(Icons.share, color: Colors.white), icon: Icons.favorite),
            ),
            _divider(),
            InkWell(
              onTap: () => _open('https://bilkil53.github.io/aile-ile-namaz-/privacy.html'),
              child: _row('Gizlilik politikası', const Icon(Icons.open_in_new, color: Colors.white),
                  icon: Icons.privacy_tip),
            ),
            if (!guest) ...[
              _divider(),
              InkWell(
                onTap: _deleteAccount,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: const [
                    Icon(Icons.delete_forever, color: AppColors.missedCoral, size: 20),
                    SizedBox(width: 10),
                    Text('Hesabımı ve verilerimi sil',
                        style: TextStyle(fontSize: 15, color: AppColors.missedCoral, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 6),
          ]),
          const SizedBox(height: 16),
          Center(
            child: Text('Aile ile Namaz v$_version · Flutter + Supabase',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}
