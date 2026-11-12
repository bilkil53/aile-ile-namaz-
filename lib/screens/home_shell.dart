import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../content/family_message.dart';
import '../cuma_reminder.dart';
import '../lang.dart';
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
import '../ui_test_mode.dart';
import '../widgets/pro_lock.dart';
import 'karne_screen.dart';
import 'kaza_screen.dart';
import 'login_screen.dart';
import 'notify_health_screen.dart';
import 'family_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

/// Ana iskelet: yeşil üst bar + alt menü (Bugün, Aile Havuzu, Kaza, Karne).
/// Ücretsiz sürümde (deneme bitti, Pro yok): Bugün'de işaretleme serbest; Kaza ve Karne kilitli (Pro penceresi).
/// Aile sekmesi açılır ama içi pasiftir (durumlar "–", işlemler Pro ister); yalnızca havuza katılma
/// serbesttir: Aile Reisi Pro alınca aileye katılan üye de Pro olur.
abstract final class HomeShellTabs {
  static bool locked(int i, {required bool demo}) => demo && (i == 2 || i == 3);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  void _selectTab(int i) {
    if (HomeShellTabs.locked(i, demo: Pro.isDemo)) {
      final names = [t('Bugün', 'Today'), t('Aile Havuzu', 'Family'), t('Kaza', 'Kaza'), t('Karne', 'Report')];
      unawaited(showProRequired(context, feature: names[i]));
      return;
    }
    setState(() => _tab = i);
  }


  RealtimeChannel? _events;
  final Map<String, String> _names = {};

  @override
  void initState() {
    super.initState();
    Pro.changed.addListener(_onProChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // İmza kontrolü her şeyden önce: tutmazsa uygulama açılmaz (fail-closed), aşağıdakiler başlamaz
      if (mounted) await Integrity.check(context);
      if (!mounted) return;
      if (isGuest && !LocalStore.guestMode) {
        final loggedIn = await showWelcome(context);
        if (loggedIn || !mounted) return; // giriş yapıldıysa yeni oturum ekranı açılır
      }
      if (!isGuest) await Kvkk.attach(); // giriş ekranında verilen rıza bu hesaba bağlanır
      // Bu telefonda kayıt yoksa önce sunucuya bakılır: başka telefonda verilmişse yeniden sorulmaz
      if (!isGuest && !Kvkk.given) await Kvkk.needsServerConsent();
      if (!isGuest && !Kvkk.given && mounted) {
        await Kvkk.askIfNeeded(context);
        if (isGuest || !mounted) return; // kabul etmediyse oturum kapandı
      }
      _startupConsentDone = true;
      if (!isGuest) {
        unawaited(_consentCheck());
        unawaited(Pro.init().then((_) => Pro.loadRequests()));
        if (LocalStore.guestMode) await LocalStore.setGuestMode(false);
        // Ağ işlerini arka planda başlat (internet yavaş/yoksa ekranı bekletmez)
        unawaited(() async {
          await Repo.syncNow();
          await _listenFamily();
          // Uygulama kapalıyken de aile bildirimleri için cihazı kaydet (FCM)
          await Push.register();
        }());
        // Bir kez sorulan sorular hemen (internet beklemeden)
        if (mounted) await _firstRunQuestions();
      }
      // Konum otomatik (GPS) → vakitler → hatırlatmalar
      if (!kUiTest) {
        await LocationHelper.autoUpdate();
        await Notifications.requestPermission();
      }
      // Eksik bildirim ayarı (izin, kesin alarm, pil tasarrufu) varsa bir kez göster
      if (!isGuest && !Pro.isDemo && mounted) await NotifyHealth.maybeShowOnce(context); // ücretsizde bildirim yok
      await Notifications.reschedule();
    });
  }

  /// Uygulamaya geri dönülünce (arka plandan) konum 1 saatten eskiyse yenilenir.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!kUiTest) unawaited(LocationHelper.autoUpdate(maxAge: const Duration(hours: 1)));
      Repo.invalidatePools(); // havuz bu arada değişmiş olabilir
      unawaited(Repo.syncNow()); // telefonda bekleyen işaretleri gönder
      unawaited(Pro.refresh()); // reis Pro aldıysa aile de hemen Pro olsun
      unawaited(Pro.loadRequests()); // reise gelen Pro istekleri
      unawaited(_consentCheck()); // sunucuda geçerli açık rıza yoksa yeniden sorulur
    }
  }

  bool _consentBusy = false;
  bool _startupConsentDone = false; // açılıştaki rıza adımı bitti mi (öncesinde ikinci pencere açılmaz)

  /// Beyanları sunucuya yazar; sunucuda geçerli açık rıza yoksa (verilmemiş ya da metin sürümü
  /// eskimiş) her açılışta ve öne gelişte yeniden sorar. Vazgeçilirse oturum kapanır.
  Future<void> _consentCheck() async {
    // Açılıştaki pencere hâlâ açıksa ikinci pencere açılmasın
    if (isGuest || _consentBusy || !_startupConsentDone) return;
    _consentBusy = true;
    try {
      // Kayıt daha önce silinmiş ama pencere gösterilememişse (ekran o an kapalıydı) şimdi sorulur
      if (Kvkk.given) await Kvkk.syncServer();
      final ask = await Kvkk.needsServerConsent() || !Kvkk.given;
      // Üstte başka bir pencere ya da sayfa açıksa (ör. Pro, ayarlar) onun üstüne binmesin:
      // kapanmasını bekle. Bu arada sunucu, rızası geçerli olmayanın bilgisini aileye zaten göstermez.
      // En çok 10 dakika beklenir; sonra bırakılır, bir sonraki öne gelişte yeniden bakılır
      for (var i = 0; i < 1200 && ask && mounted && !isGuest && !(ModalRoute.of(context)?.isCurrent ?? true); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (ask && mounted && !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (ask && mounted && !isGuest) {
        await Kvkk.askIfNeeded(context);
        if (!isGuest) await Kvkk.syncServer();
      }
    } finally {
      _consentBusy = false;
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
          scrollable: true, // küçük ekran / büyük yazıda taşmasın
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          icon: const Icon(Icons.lock_outline, color: AppColors.emerald, size: 32),
          title: Text(t('Telefon kilitliyken bildirimler', 'Notifications on the lock screen'), style: const TextStyle(fontSize: 17)),
          content: Text(
            t(
              'Aileden biri namaz kılınca veya dua gönderince bildirim gelir.\n\n'
                  'Telefon kilitliyken bildirimin yazısı kilit ekranında görünsün mü? '
                  '"Gizle" dersen sadece "yeni bildirim" görünür, yazı kilidi açınca okunur.\n\n'
                  'Bunu sonra Ayarlar\'dan değiştirebilirsin.',
              'You get a notification when a family member prays or sends a dua.\n\n'
                  'Should the notification text be visible on the lock screen? '
                  'If you choose "Hide", only "new notification" is shown; the text is readable after unlocking.\n\n'
                  'You can change this later in Settings.',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Göster', 'Show'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Gizle (önerilen)', 'Hide (recommended)')),
            ),
          ],
        ),
      );
      await AppSettings.setNotify('lockScreen', show ?? false);
      await p.setBool('askedLockScreen', true);
      unawaited(Push.register());
    }
  }

  /// Pro ↔ Demo değişince: kilitli sekmeden çık, bildirimleri aç/kapat.
  void _onProChanged() {
    if (!mounted) return;
    // Pro süresi açıkken bitti: kilitli sekmede kalınmaz, Bugün'e dönülür
    setState(() {
      if (HomeShellTabs.locked(_tab, demo: Pro.isDemo)) _tab = 0;
    });
    unawaited(Push.register()); // demo'da kaydı siler, Pro'da yeniden kaydeder
    unawaited(Notifications.reschedule()); // demo'da hepsini iptal eder
  }

  @override
  void dispose() {
    Pro.changed.removeListener(_onProChanged);
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
        if (me != null) unawaited(CumaReminder.rememberGender(genderOf(me)));
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
            if (type == 'PRO_REQUEST') unawaited(Pro.loadRequests()); // reisin ekranındaki kart
            if (((type == 'PRAYED' || type == 'ALL_PRAYED') && !AppSettings.notifyPrayer) ||
                (type == 'KAZA' && !AppSettings.notifyKaza) ||
                (type == 'DUA' && !AppSettings.notifyDua)) {
              return;
            }
            final who = _names[r['sender_id']] ?? t('Aile ferdin', 'A family member');
            final prayer = prayerLabels[(r['prayer'] as String?)?.toLowerCase()] ?? '';
            final (title, body) = switch (r['event_type']) {
              'PRAYED' => (t('$who namazını kıldı 🤲', '$who prayed 🤲'),
                  t('$prayer namazını kıldı. Allah kabul etsin.', 'Prayed $prayer. May Allah accept it.')),
              'ALL_PRAYED' => (t('$who 5 vaktin hepsini kıldı 🌟', '$who prayed all 5 prayers 🌟'),
                  t('Maşallah! Günün bütün namazlarını eda etti. Allah kabul etsin.',
                      'Masha\'Allah! Completed all of the day\'s prayers. May Allah accept them.')),
              'KAZA' => (t('$who kaza namazı kıldı', '$who made up a missed prayer'),
                  t('Bir kaza namazı eda etti.', 'Completed one kaza prayer.')),
              'DUA' => (
                  r['target_id'] == myId
                      ? t('$who sana dua gönderdi 🤲', '$who sent you a dua 🤲')
                      : t('$who aileye dua gönderdi 🤲', '$who sent the family a dua 🤲'),
                  ((r['message'] as String?) ?? '').isNotEmpty
                      ? familyMessageText(r['message'] as String)
                      : t('Allah ibadetlerimizi kabul etsin.', 'May Allah accept our worship.')),
              'MEMBER_JOINED' => (t('Aile havuzuna katılım 🤝', 'New family member 🤝'),
                  t('${r['message'] ?? 'Yeni bir ferd'} aile havuzuna katıldı.',
                      '${r['message'] == null ? 'A new member' : roleText(r['message'] as String)} joined the family circle.')),
              'PRO_REQUEST' => (t('$who Pro istiyor 🌟', '$who wants Pro 🌟'),
                  t('Aile Pro\'sunu alırsan havuzdaki herkes Pro olur.', 'If you get Family Pro, everyone in the circle becomes Pro.')),
              _ => ('', ''),
            };
            if (title.isEmpty) return;
            Notifications.showFamily((r['id'] as num?)?.toInt() ?? 0, title, body);
          },
        )
        .subscribe();
  }

  static List<String> get _subtitles => [
        t('Vakitler & Günlük İbadet', 'Prayer Times & Daily Worship'),
        t('Aile Havuzu (İbadet Halkası)', 'Family Circle (Worship Circle)'),
        t('Kaza Namazı Yönetimi', 'Missed (Kaza) Prayers'),
        t('İbadet Karnesi & İstatistik', 'Worship Report & Stats'),
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
                  Row(children: [
                    const Text(
                      'Aile ile Namaz',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    if (kTestChannel && !isGuest)
                      ValueListenableBuilder<int>(
                        valueListenable: Pro.changed,
                        builder: (_, __, ___) => !Pro.isTester ? const SizedBox.shrink() : Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(Pro.testLabel(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF78350F))),
                        ),
                      ),
                  ]),
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
            onTap: _selectTab,
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppColors.white,
            selectedItemColor: AppColors.emerald,
            unselectedItemColor: AppColors.textSecondary,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
            items: [
              BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: t('Bugün', 'Today')),
              BottomNavigationBarItem(icon: Icon(Icons.diversity_1_outlined), activeIcon: Icon(Icons.diversity_1), label: t('Aile Havuzu', 'Family')),
              BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), activeIcon: Icon(Icons.calendar_month), label: t('Kaza', 'Kaza')),
              BottomNavigationBarItem(icon: Icon(Icons.emoji_events_outlined), activeIcon: Icon(Icons.emoji_events), label: t('Karne', 'Report')),
            ],
          ),
        ),
      ),
    );
  }
}
