import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data.dart';
import '../integrity.dart';
import '../pro.dart';
import '../kvkk.dart';
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
      if (!isGuest && !Kvkk.given && mounted) {
        await Kvkk.askIfNeeded(context);
        if (isGuest || !mounted) return; // kabul etmediyse oturum kapandı
      }
      if (!isGuest) {
        unawaited(Kvkk.syncServer());
        unawaited(Pro.init());
        if (LocalStore.guestMode) await LocalStore.setGuestMode(false);
        // Ağ işlerini arka planda başlat (internet yavaş/yoksa ekranı bekletmez)
        unawaited(() async {
          try {
            await Repo.migrateGuestData().timeout(const Duration(seconds: 20));
          } catch (_) {}
          await Repo.syncNow();
          await _listenFamily();
          // Uygulama kapalıyken de aile bildirimleri için cihazı kaydet (FCM)
          await Push.register();
        }());
        // Bir kez sorulan sorular hemen (internet beklemeden)
        if (mounted) await _firstRunQuestions();
      }
      if (mounted) await Integrity.check(context);
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
      unawaited(Repo.syncNow()); // telefonda bekleyen işaretleri gönder
    }
  }

  /// Bir kez sorulan soru: kilit ekranında bildirim içeriği.
  Future<void> _firstRunQuestions() async {
    final p = AppSettings.prefs;
    if (!(p.getBool('askedLockScreen') ?? false)) {
      final show = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          icon: const Icon(Icons.lock_outline, color: AppColors.emerald, size: 32),
          title: const Text('Telefon kilitliyken bildirimler', style: TextStyle(fontSize: 17)),
          content: const Text(
            'Aileden biri namaz kılınca veya dua gönderince bildirim gelir.\n\n'
            'Telefon kilitliyken bildirimin yazısı kilit ekranında görünsün mü? '
            '"Gizle" dersen sadece "yeni bildirim" görünür, yazı kilidi açınca okunur.\n\n'
            'Bunu sonra Ayarlar\'dan değiştirebilirsin.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Gizle')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Göster'),
            ),
          ],
        ),
      );
      await AppSettings.setNotify('lockScreen', show ?? true);
      await p.setBool('askedLockScreen', true);
      unawaited(Push.register());
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
        final ms = await Repo.members(p.id);
        final me = ms.where((x) => x.userId == myId).firstOrNull;
        final reis = ms.where((x) => x.userId == p.ownerId).firstOrNull;
        for (final m in ms) {
          final label = me == null ? m.labelFor(viewerIsReis: p.ownerId == myId) : kinLabel(viewer: me, target: m, reis: reis);
          // Ad yalnızca çocuklarda ya da aynı ünvanlı birden fazla kişi varsa ("Kızın Ayşe")
          final same = ms.where((x) => x.roleTitle.isNotEmpty && x.roleTitle == m.roleTitle).length;
          final needName = const {'Oğlu', 'Kızı', 'Torunu'}.contains(m.roleTitle) || same > 1;
          _names[m.userId] = '${m.icon} ${needName ? withFirstName(label, m.firstName) : label}';
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
            if (r['target_id'] != null && r['target_id'] != myId) return; // başkasına özel dua
            // Arka plandayken bildirimi FCM gösterir; çift bildirim olmasın
            if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
            final type = r['event_type'] as String?;
            if ((type == 'PRAYED' && !AppSettings.notifyPrayer) ||
                (type == 'KAZA' && !AppSettings.notifyKaza) ||
                (type == 'DUA' && !AppSettings.notifyDua)) return;
            final who = _names[r['sender_id']] ?? 'Aile ferdin';
            final prayer = prayerLabels[(r['prayer'] as String?)?.toLowerCase()] ?? '';
            final (title, body) = switch (r['event_type']) {
              'PRAYED' => ('$who namazını kıldı 🤲', '$prayer namazını kıldı. Allah kabul etsin.'),
              'KAZA' => ('$who kaza namazı kıldı', 'Bir kaza namazı eda etti.'),
              'DUA' => (r['target_id'] == myId ? '$who sana dua gönderdi 🤲' : '$who aileye dua gönderdi 🤲',
                  (r['message'] as String?) ?? ''),
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
