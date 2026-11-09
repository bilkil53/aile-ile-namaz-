import 'dart:async';

import 'package:flutter/material.dart';
import '../config.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
import '../pro.dart';
import '../widgets/pro_lock.dart';
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
  String _lastSync = '';
  bool _exact = true;

  void _proRebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Pro.changed.removeListener(_proRebuild);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Pro.changed.addListener(_proRebuild);
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
    return d == null ? '' : DateFormat('d MMMM yyyy', 'tr').format(d);
  }

  /// Önbelleği temizle: telefondaki vakit önbelleği ve aile özeti silinir.
  /// Namaz kayıtların, bekleyen gönderimler ve bulut verin silinmez.
  Future<void> _clearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Önbelleği temizle', style: TextStyle(fontSize: 17)),
        content: const Text('Telefonda saklanan namaz vakitleri ve aile havuzu özeti silinir, internetten yeniden alınır.\n\n'
            'Namaz kayıtların, kaza sayıların ve buluttaki verilerin silinmez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Temizle')),
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
    _toast(n == 0 ? 'Önbellek zaten temiz ✓' : 'Önbellek temizlendi ✓ ($n kayıt)');
  }

  /// Anlık bildirim hatası: ayrıntı + kopyala + tekrar dene (destek için).
  Future<void> _pushProblem() async {
    final detail = Push.lastErrorDetail.isEmpty ? Push.status.value : Push.lastErrorDetail;
    final again = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anlık bildirim hatası', style: TextStyle(fontSize: 17)),
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
              _toast('Hata ayrıntısı kopyalandı. Geliştiriciye gönderebilirsin.');
            },
            child: const Text('Kopyala'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tekrar dene')),
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
    final sent = await Repo.syncNowCount();
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
          title: const Text('Gönderilmemiş kayıt var'),
          content: Text('$left kayıt henüz buluta gönderilemedi (internet yok olabilir). '
              'Çıkış yaparsan bu kayıtlar telefondan silinir.\n\nİnternet gelince otomatik gönderilmesi için '
              'şimdilik çıkış yapmaman önerilir.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.missed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yine de çıkış yap'),
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

  /// 🧪 Test Paneli (yalnızca Namaz Demo): durumlar arasında hızlı geçiş, gerçek akıştan ayrı.
  Widget _testPanel() => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF59E0B), width: 2),
        ),
        child: ValueListenableBuilder<int>(
          valueListenable: Pro.changed,
          builder: (_, __, ___) => FutureBuilder<bool>(
            future: Pro.isReis(),
            builder: (context, snap) {
              final reis = snap.data ?? true;
              const brown = Color(0xFF78350F);
              Widget btn(String label, IconData icon, Future<void> Function()? onTap) => OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: brown,
                      side: const BorderSide(color: Color(0xFFF59E0B)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: onTap == null
                        ? null
                        : () async {
                            await onTap();
                            if (mounted) setState(() {});
                          },
                    icon: Icon(icon, size: 18),
                    label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('🧪 Test Paneli',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: brown)),
                const SizedBox(height: 4),
                Text('Şu an: ${Pro.testLabel().replaceFirst('🧪 ', '')}',
                    style: const TextStyle(fontSize: 13, color: brown)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  btn('Denemeyi baştan başlat (7 gün)', Icons.play_arrow, Pro.testRestartTrial),
                  btn('Denemeyi bitir → Ücretsiz', Icons.stop, Pro.expireTest),
                  btn(reis ? 'Pro yap (test)' : 'Pro yap: Pro\'yu reis alır', Icons.workspace_premium,
                      reis ? () async => await Pro.redeem('1') : null),
                  btn('Pro\'yu kaldır', Icons.close, Pro.testRemovePro),
                ]),
                const SizedBox(height: 6),
                const Text('Bu panel yalnızca test sürümünde görünür; gerçek kullanıcılar görmez.',
                    style: TextStyle(fontSize: 11, color: brown)),
              ]);
            },
          ),
        ),
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
        title: Text('Sürüm v$_version', style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(_notes.isEmpty ? 'Sürüm açıklaması alınamadı. İnternet bağlantını kontrol et.' : _notes,
                style: const TextStyle(fontSize: 12, height: 1.4)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => _open('$_repo/releases/latest'), child: const Text('GitHub\'da aç')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tamam')),
        ],
      ),
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
    final pending = LocalStore.pendingCount;
    final user = supa.auth.currentUser;
    final name = (user?.userMetadata?['full_name'] ?? user?.userMetadata?['name'] ?? '') as String;
    final email = user?.email ?? '';
    final syncText = guest
        ? 'Gezinti modu · kayıt yapılmaz'
        : (_syncing
            ? 'Gönderiliyor…'
            : (pending > 0
                ? '⏳ $pending kayıt bekliyor · göndermek için dokun'
                : 'Bulut senkronize ☁️${_lastSync.isEmpty ? '' : ' · Son: $_lastSync'}'));
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1) Hesap
          _bigCard([
            _title('Hesap'),
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
                  Text(guest ? 'Gezinti modu' : (name.isEmpty ? 'Google hesabı' : name),
                      style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
                  if (!guest && email.isNotEmpty)
                    Text(email, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
                  if (!guest && _fmtDate(user?.createdAt).isNotEmpty)
                    Text('Üyelik: ${_fmtDate(user?.createdAt)}'
                        '${_fmtDate(user?.lastSignInAt).isEmpty ? '' : ' · Son giriş: ${_fmtDate(user?.lastSignInAt)}'}',
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            InkWell(
              onTap: guest || _syncing ? null : _sync,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(guest ? Icons.phone_android : (pending > 0 ? Icons.cloud_upload : Icons.cloud_done),
                      color: AppColors.prayedMint, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(syncText,
                        style: const TextStyle(fontSize: 14, color: AppColors.prayedMint, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            if (guest)
              _whiteBtn('Google ile Giriş Yap', () async {
                Navigator.of(context).popUntil((r) => r.isFirst);
                await LocalStore.setGuestMode(false);
              }, icon: Icons.login)
            else
              Align(
                alignment: Alignment.centerLeft,
                child: _outlineBtn('Çıkış Yap', _signOut, icon: Icons.logout),
              ),
            if (!guest) ...[
              _divider(),
              ValueListenableBuilder<int>(
                valueListenable: Pro.changed,
                builder: (_, __, ___) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Satırların kendi simgesi var (🕒 / 🔒 / ⭐); ayrıca simge gösterilmez
                    Text(
                      Pro.statusText(),
                      style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    ValueListenableBuilder<Map<String, DateTime>>(
                      valueListenable: Pro.requests,
                      builder: (_, reqs, __) => reqs.isEmpty || Pro.source == 'paid'
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('📩 Pro istedi: ${reqs.keys.map((id) => Pro.requestNames[id] ?? 'Aile ferdin').join(', ')}',
                                  style: const TextStyle(fontSize: 13, color: AppColors.gold, fontWeight: FontWeight.bold)),
                            ),
                    ),
                    const SizedBox(height: 8),
                    _outlineBtn('Pro\'ya geç', () => showProCodeDialog(context), icon: Icons.workspace_premium),
                  ]);
                },
              ),
            ],
            const SizedBox(height: 6),
          ]),
          if (kTestChannel && !guest) ...[const SizedBox(height: 14), _testPanel()],
          const SizedBox(height: 14),
          // 2) Uygulama
          _bigCard([
            _title('Uygulama'),
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
                        ? 'Konum izni yok — İstanbul vakitleri gösteriliyor'
                        : 'GPS ile otomatik · sadece telefonda tutulur',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
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
            InkWell(
              onTap: _showNotes,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 20, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Sürüm v$_version',
                          style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
                      Text('Sürüm notları için dokun',
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
                    child: Text(hasUpdate ? 'Güncelleme var!' : '✓ Güncel',
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
                  const Text('Yeni Güncelleme Hazır 🎉',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF78350F))),
                  if (_notes.isNotEmpty)
                    Text(_notes, maxLines: 6, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF78350F))),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
                    onPressed: () => UpdateChecker.install(context, _latest!),
                    icon: const Icon(Icons.system_update, size: 18),
                    label: const Text('Hemen Güncelle'),
                  ),
                ]),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: _outlineBtn(_checking ? 'Sorgulanıyor…' : 'Güncellemeleri Kontrol Et', _checking ? null : _check),
              ),
            _divider(),
            _tapRow('Önbelleği temizle', Icons.cleaning_services_outlined, _clearCache,
                sub: 'Vakitler ve aile özeti yeniden alınır · kayıtların silinmez'),
            const SizedBox(height: 6),
          ]),
          const SizedBox(height: 14),
          // 3) Diğer
          _bigCard([
            _title('Diğer'),
            _divider(),
            _tapRow('Uygulamayı paylaş', Icons.share, () async {
              // Telefonun paylaşım penceresi: WhatsApp, Gmail, Mesajlar, Telegram…
              await Share.share(
                '🕌 Aile ile Namaz — ailenle birlikte namaz takibi, kaza takibi ve aile havuzu.\n\n'
                'Android için indir: $_repo/releases/latest/download/aile-ile-namaz.apk',
                subject: 'Aile ile Namaz uygulaması',
              );
            }),
            _tapRow('Öneri yaz', Icons.mail_outline, _mail, sub: 'Mail uygulaması açılır'),
            _tapRow('GitHub', Icons.star_rounded, () => _open(_repo),
                sub: 'Kaynak kod · Yıldız ver ⭐',
                trailing: const Icon(Icons.open_in_new, color: Colors.white, size: 18)),
            _tapRow('Gizlilik politikası', Icons.privacy_tip_outlined,
                () => _open('https://bilkil53.github.io/aile-ile-namaz-/privacy.html'),
                trailing: const Icon(Icons.open_in_new, color: Colors.white, size: 18)),
            const SizedBox(height: 6),
          ]),
          const SizedBox(height: 14),
          // 4) Bildirimler (demo'da tamamen kapalı)
          if (Pro.isDemo)
            _bigCard([
              _title('Bildirimler'),
              _divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(children: [
                  const Icon(Icons.notifications_off_outlined, color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                      child: Text('Ücretsiz sürümde bildirimler kapalı · Pro ile açılır',
                          style: TextStyle(color: Colors.white70, fontSize: 13))),
                  TextButton(onPressed: () => showProCodeDialog(context), child: const Text('Pro kodu')),
                ]),
              ),
            ])
          else
          _bigCard([
            _title('Bildirimler'),
            _divider(),
            _tapRow('Bildirim izinlerini kontrol et', Icons.health_and_safety_outlined,
                () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotifyHealthScreen())),
                sub: 'İzin, kesin alarm, pil tasarrufu · test bildirimi',
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
                              child: Text('Uygulama kapalıyken aile bildirimleri gelmeyebilir: $s · tekrar denemek için dokun',
                                  style: const TextStyle(fontSize: 12, color: Colors.white)),
                            ),
                          ]),
                        ),
                      ),
              ),
            const SizedBox(height: 6),
          ]),
          // 5) Hesabı sil (en altta)
          if (!guest) ...[
            const SizedBox(height: 18),
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
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Hesabımı ve verilerimi sil',
                            style: TextStyle(fontSize: 14, color: AppColors.missed, fontWeight: FontWeight.bold)),
                        Text('Tüm kayıtların kalıcı olarak silinir',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ]),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.missed.withValues(alpha: 0.7)),
                  ]),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
