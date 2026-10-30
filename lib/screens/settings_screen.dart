import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../location.dart';
import '../notifications.dart';
import '../settings.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  bool _gpsBusy = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = '${i.version} (${i.buildNumber})');
    });
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _gps() async {
    setState(() => _gpsBusy = true);
    try {
      final (ok, msg) = await LocationHelper.updateFromGps();
      _toast(ok ? 'Konum güncellendi: $msg' : msg);
      if (ok) unawaited(Notifications.reschedule());
      if (mounted) setState(() {});
    } catch (_) {
      _toast('Konum alınamadı.');
    } finally {
      if (mounted) setState(() => _gpsBusy = false);
    }
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(title.toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.emerald, letterSpacing: 0.8)),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(children: children),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final email = supa.auth.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ayarlar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Uygulama Bilgileri', style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Konum ve vakitler', [
            ListTile(
              leading: const Icon(Icons.location_on, color: AppColors.emerald),
              title: Text(AppSettings.cityName),
              subtitle: const Text('Konum GPS ile otomatik bulunur. Sadece telefonda tutulur, sunucuya gönderilmez.'),
            ),
            const Divider(height: 1),
            if (LocationHelper.permissionDenied)
              ListTile(
                leading: const Icon(Icons.location_off, color: AppColors.gold),
                title: const Text('Konum izni ver'),
                subtitle: const Text('İzin olmadan İstanbul vakitleri gösterilir.'),
                onTap: LocationHelper.openSettings,
              ),
            ListTile(
              leading: const Icon(Icons.my_location, color: AppColors.emerald),
              title: const Text('Konumu şimdi yenile'),
              trailing: _gpsBusy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: _gpsBusy ? null : _gps,
            ),
          ]),
          _section('Bildirimler', [
            SwitchListTile(
              secondary: const Icon(Icons.alarm, color: AppColors.emerald),
              title: const Text('Vakit hatırlatması'),
              subtitle: Text('Her vakitten ${AppSettings.reminderMinutes} dakika önce'),
              value: AppSettings.prayerReminders,
              onChanged: (v) async {
                await AppSettings.setPrayerReminders(v);
                if (v) await Notifications.requestPermission();
                unawaited(Notifications.reschedule());
                setState(() {});
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.menu_book, color: AppColors.emerald),
              title: const Text('Günün ayeti / hadisi'),
              subtitle: const Text('Her gün 12:00\'de'),
              value: AppSettings.dailyContent,
              onChanged: (v) async {
                await AppSettings.setDailyContent(v);
                if (v) await Notifications.requestPermission();
                unawaited(Notifications.reschedule());
                setState(() {});
              },
            ),
          ]),
          _section('Hesap', [
            ListTile(
              leading: const Icon(Icons.account_circle, color: AppColors.emerald),
              title: const Text('Giriş yapılan hesap'),
              subtitle: Text(email),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.emerald),
              title: const Text('Gizlilik politikası'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => launchUrl(
                Uri.parse('https://bilkil53.github.io/aile-ile-namaz-/privacy.html'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.missed),
              title: const Text('Çıkış yap', style: TextStyle(color: AppColors.missed)),
              onTap: () async {
                Navigator.of(context).pop();
                await supa.auth.signOut();
              },
            ),
          ]),
          Center(
            child: Text('Aile ile Namaz · Sürüm $_version',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}
