import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data.dart';
import '../local_store.dart';
import '../location.dart';
import '../models.dart';
import '../settings.dart';
import '../notifications.dart';
import '../push.dart';

import '../theme.dart';
import 'karne_screen.dart';
import 'kaza_screen.dart';
import 'login_screen.dart';
import 'family_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

/// Ana iskelet: yeşil üst bar + alt menü (Bugün, Aile Havuzu, Kaza, Karne).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  RealtimeChannel? _events;
  final Map<String, String> _names = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (isGuest && !LocalStore.guestMode) {
        final loggedIn = await showWelcome(context);
        if (loggedIn || !mounted) return; // giriş yapıldıysa yeni oturum ekranı açılır
      }
      if (!isGuest) {
        if (LocalStore.guestMode) await LocalStore.setGuestMode(false);
        // Misafirken girilenleri ve çevrimdışı bekleyenleri buluta gönder
        try {
          await Repo.migrateGuestData();
        } catch (_) {}
        await Repo.flushQueue();
        _listenFamily();
        // Uygulama kapalıyken de aile bildirimleri için cihazı kaydet (FCM)
        unawaited(Push.register());
      }
      // Konum otomatik (GPS) → vakitler → hatırlatmalar
      await LocationHelper.autoUpdate();
      await Notifications.requestPermission();
      await Notifications.reschedule();
    });
  }

  /// Uygulamaya geri dönülünce (arka plandan) konum 1 saatten eskiyse yenilenir.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(LocationHelper.autoUpdate(maxAge: const Duration(hours: 1)));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_events != null) supa.removeChannel(_events!);
    super.dispose();
  }

  /// Aileden biri namaz kılınca / dua gönderince telefona bildirim (uygulama açıkken).
  Future<void> _listenFamily() async {
    try {
      for (final p in await Repo.myPools()) {
        for (final m in await Repo.members(p.id)) {
          _names[m.userId] = m.labelFor(viewerIsReis: p.ownerId == myId);
        }
      }
    } catch (_) {}
    _events = supa
        .channel('family-alerts-$myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'pool_events',
          callback: (payload) {
            final r = payload.newRecord;
            if (r['sender_id'] == myId || !AppSettings.familyAlerts) return;
            // Arka plandayken bildirimi FCM gösterir; çift bildirim olmasın
            if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
            final who = _names[r['sender_id']] ?? 'Aile ferdin';
            final prayer = prayerLabels[(r['prayer'] as String?)?.toLowerCase()] ?? '';
            final (title, body) = switch (r['event_type']) {
              'PRAYED' => ('$who namazını kıldı 🤲', '$prayer namazını kıldı. Allah kabul etsin.'),
              'KAZA' => ('$who kaza namazı kıldı', 'Bir kaza namazı eda etti.'),
              'DUA' => ('$who dua gönderdi 🤲', (r['message'] as String?) ?? ''),
              'MEMBER_JOINED' => ('Aile havuzuna katılım 🤝', '${r['message'] ?? 'Yeni bir ferd'} aile havuzuna katıldı.'),
              _ => ('', ''),
            };
            if (title.isEmpty) return;
            Notifications.showFamily((r['id'] as num?)?.toInt() ?? 0, title, body);
          },
        )
        .subscribe();
  }

  static const _subtitles = [
    'Vakitler & Günlük İbadet',
    'Aile Havuzu (İbadet Halkası)',
    'Kaza Namazı Yönetimi',
    'İbadet Karnesi & İstatistik',
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mosque, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Aile ile Namaz',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    _subtitles[_tab],
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.88)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.settings, size: 19, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: const [
            TodayScreen(),
            FamilyScreen(),
            KazaScreen(),
            KarneScreen(),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.cardBorder, width: 0.5)),
          ),
          child: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppColors.white,
            selectedItemColor: AppColors.emerald,
            unselectedItemColor: AppColors.textSecondary,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Bugün'),
              BottomNavigationBarItem(icon: Icon(Icons.diversity_1_outlined), activeIcon: Icon(Icons.diversity_1), label: 'Aile Havuzu'),
              BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), activeIcon: Icon(Icons.calendar_month), label: 'Kaza'),
              BottomNavigationBarItem(icon: Icon(Icons.emoji_events_outlined), activeIcon: Icon(Icons.emoji_events), label: 'Karne'),
            ],
          ),
        ),
      ),
    );
  }
}
