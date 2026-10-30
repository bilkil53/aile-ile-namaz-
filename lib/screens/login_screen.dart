import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  final _google = GoogleSignIn(
    serverClientId: AppConfig.googleWebClientId,
    scopes: const ['email', 'profile'],
  );

  /// 1) Telefondaki Google hesaplarından seçtirir (tarayıcı açılmaz).
  /// 2) Bu yol çalışmazsa (ör. cihazda Google Play Hizmetleri yok) tarayıcı girişine düşer.
  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      final ok = await _nativeSignIn();
      if (!ok) return; // kullanıcı hesap seçimini kapattı
    } catch (_) {
      try {
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: AppConfig.authRedirect,
          queryParams: {'prompt': 'select_account'},
        );
      } catch (_) {
        _toast('Giriş yapılamadı. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// true: giriş yapıldı, false: kullanıcı vazgeçti. Hata olursa fırlatır.
  Future<bool> _nativeSignIn() async {
    // Önceki seçimi temizle ki her seferinde hesap listesi gelsin.
    await _google.signOut();
    final account = await _google.signIn();
    if (account == null) return false;
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) throw Exception('idToken alınamadı');
    await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: auth.accessToken,
    );
    return true;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🕌', style: TextStyle(fontSize: 72)),
                const SizedBox(height: 16),
                Text('Aile İle Namaz', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Ailenle birlikte namaz takibi',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 48),
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Google ile giriş yap'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
