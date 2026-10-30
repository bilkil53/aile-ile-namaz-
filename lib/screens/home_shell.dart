import 'package:flutter/material.dart';

import '../location.dart';
import '../notifications.dart';

import '../theme.dart';
import 'karne_screen.dart';
import 'kaza_screen.dart';
import 'family_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

/// Ana iskelet: yeşil üst bar + alt menü (Bugün, Aile Havuzu, Kaza, Karne).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Giriş sonrası: bildirim izni iste ve vakit hatırlatmalarını kur.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Konum otomatik (GPS) → vakitler → hatırlatmalar
      await LocationHelper.autoUpdate();
      await Notifications.requestPermission();
      await Notifications.reschedule();
    });
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
