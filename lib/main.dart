import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
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
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseKey,
  );
  unawaited(Push.init());
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aile İle Namaz',
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateChecker.check(context);
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
