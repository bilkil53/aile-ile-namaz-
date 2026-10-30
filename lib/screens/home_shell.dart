import 'package:flutter/material.dart';

import '../data.dart';
import '../theme.dart';
import 'pools_screen.dart';
import 'today_screen.dart';

/// Ana iskelet: yeşil üst bar + alt menü (Bugün, Aile Havuzu, Kaza, Karne).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

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
              child: PopupMenuButton<String>(
                tooltip: 'Ayarlar',
                icon: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: const Icon(Icons.settings, size: 19, color: Colors.white),
                ),
                onSelected: (v) {
                  if (v == 'logout') supa.auth.signOut();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'logout', child: Text('Çıkış yap')),
                ],
              ),
            ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: const [
            TodayScreen(),
            PoolsScreen(),
            _ComingSoon(
              icon: Icons.calendar_month,
              title: 'Kaza Namazı',
              text: 'Kaza borcunu ve ödediklerini buradan takip edeceksin. '
                  'Havuzdaki aile üyelerin sadece toplam sayıyı görür.',
            ),
            _ComingSoon(
              icon: Icons.emoji_events,
              title: 'İbadet Karnesi',
              text: 'Haftalık ve aylık namaz istatistiklerin burada olacak.',
            ),
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

class _ComingSoon extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _ComingSoon({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.emerald,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 6),
              Text(text, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.85))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Yakında',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
