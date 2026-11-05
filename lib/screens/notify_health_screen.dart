import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../notifications.dart';
import '../settings.dart';
import '../theme.dart';

/// Bildirimlerin düzgün gelmesi için gereken telefon ayarları (izin, kesin alarm, pil tasarrufu).
class NotifyHealth {
  static const _ch = MethodChannel('aile/exit');
  static const _kAsked = 'notifyHealthAsked';

  /// Pil tasarrufu muafiyeti var mı (Android uygulamayı uyutmaz).
  static Future<bool> batteryIgnored() async {
    try {
      return await _ch.invokeMethod<bool>('batteryIgnored') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> openBatterySettings() async {
    try {
      await _ch.invokeMethod('openBatterySettings');
    } catch (_) {}
  }

  static Future<void> openNotificationSettings() async {
    try {
      await _ch.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  static Future<(bool, bool, bool)> check() async =>
      (await Notifications.enabled(), await Notifications.exactAllowed(), await batteryIgnored());

  /// Girişten sonra bir kez: eksik ayar varsa ekranı göster.
  static Future<void> maybeShowOnce(BuildContext context) async {
    final p = AppSettings.prefs;
    if (p.getBool(_kAsked) ?? false) return;
    final (n, e, b) = await check();
    await p.setBool(_kAsked, true);
    if (n && e && b) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotifyHealthScreen()));
  }
}

class NotifyHealthScreen extends StatefulWidget {
  const NotifyHealthScreen({super.key});

  @override
  State<NotifyHealthScreen> createState() => _NotifyHealthScreenState();
}

class _NotifyHealthScreenState extends State<NotifyHealthScreen> with WidgetsBindingObserver {
  bool? _notif, _exact, _battery;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Telefon ayarlarından geri dönünce durumu yenile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final (n, e, b) = await NotifyHealth.check();
    if (!mounted) return;
    setState(() {
      _notif = n;
      _exact = e;
      _battery = b;
    });
  }

  Widget _row(String title, String sub, bool? ok, Future<void> Function() fix) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ok == false ? AppColors.missed : AppColors.cardBorder),
        ),
        child: Row(children: [
          Text(ok == null ? '…' : (ok ? '✅' : '❌'), style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          if (ok == false)
            FilledButton(
              onPressed: () async {
                await fix();
                await _refresh();
              },
              child: const Text('Aç'),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bildirim izinleri')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text('🔔 Bildirimlerin düzgün gelmesi için',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Vakit hatırlatmaları ve aile bildirimleri için üç ayarın da ✅ olması gerekir.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          _row('Bildirim izni', 'Uygulama bildirim gösterebilsin', _notif, () async {
            await Notifications.requestPermission();
            if (!await Notifications.enabled()) await NotifyHealth.openNotificationSettings();
          }),
          _row('Kesin alarm', 'Vakit hatırlatması dakikası dakikasına gelsin', _exact, Notifications.requestExact),
          _row('Pil tasarrufu muafiyeti', 'Telefon uygulamayı uyutup bildirimleri geciktirmesin', _battery,
              NotifyHealth.openBatterySettings),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.goldContainer, borderRadius: BorderRadius.circular(16)),
            child: const Text(
              'ℹ️ Samsung kullanıyorsan: Ayarlar → Pil → Arka plan kullanım sınırları → '
              '"Uyku moduna alınan uygulamalar" listesinde bu uygulama varsa çıkar.\n\n'
              'Pil tasarrufu sayfasında listeden bu uygulamayı bulup "Optimize etme" / "Kısıtlama yok" seç.',
              style: TextStyle(fontSize: 12, color: Color(0xFF78350F)),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              await Notifications.showTest();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Test bildirimi gönderildi. Bildirim çubuğuna bak.')));
            },
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('🔔 Test bildirimi gönder'),
          ),
        ],
      ),
    );
  }
}
