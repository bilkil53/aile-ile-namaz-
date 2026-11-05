import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'crash_report.dart';
import 'local_store.dart';
import 'notifications.dart';
import 'push.dart';
import 'settings.dart';
import 'screens/home_shell.dart';
import 'theme.dart';
import 'update_checker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    initializeDateFormatting('tr'),
    AppSettings.init(),
  ]);
  await LocalStore.cleanupLegacy();
  unawaited(Notifications.init());
  // İnternet yokken uygulama açılışta beklemesin: oturum telefondan yüklenir, süresi dolmuş
  // oturumun yenilenmesi bağlantı gelince arka planda tamamlanır. En fazla 3 sn beklenir.
  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseKey,
    ).timeout(const Duration(seconds: 3));
  } catch (_) {
    // Çevrimdışı / zaman aşımı: istemci hazır, uygulama yerel verilerle açılır
  }
  unawaited(CrashReport.install());
  unawaited(Push.init());
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aile İle Namaz',
      navigatorKey: CrashReport.navigatorKey,
      // Telefonun büyük yazı ayarı uygulamayı büyütmesin (ekranlar ve pencereler taşmasın)
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.0)),
          child: child!,
        );
      },
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const AuthGate(),
    );
  }
}

/// Oturum açıksa havuz listesi, değilse giriş ekranı.
/// Açılışta GitHub'da yeni sürüm olup olmadığını da kontrol eder.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Açılışta oturum telefondan yüklenene kadar beklenir (en fazla 5 sn); yoksa ilk saniyelerde
  /// giriş yapmış kullanıcı kısa bir an "misafir" sanılır ve o arada işaretlenen kayıt kaybolabilir.
  bool _waited = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _waited = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateChecker.check(context);
      CrashReport.checkLastExit();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return ValueListenableBuilder<int>(
      valueListenable: LocalStore.guestChanged,
      builder: (context, _, __) => StreamBuilder<AuthState>(
        stream: auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = auth.currentSession;
          if (session == null && !snapshot.hasData && !_waited) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (session != null) {
            return HomeShell(key: ValueKey(session.user.id));
          }
          // Giriş yoksa uygulama açılır; ilk açılışta üzerine "Hoş Geldiniz" penceresi gelir.
          return HomeShell(key: ValueKey('guest-${LocalStore.guestMode}'));
        },
      ),
    );
  }
}
