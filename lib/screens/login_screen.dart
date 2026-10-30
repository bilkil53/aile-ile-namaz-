import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../theme.dart';

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
    return Scaffold(
      backgroundColor: AppColors.emerald,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mosque, size: 46, color: Colors.white),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Aile ile Namaz',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ailenle birlikte, vaktinde.',
                  style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 36),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Selamün aleyküm',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Telefonundaki Google hesabını seçerek hemen başla.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.emerald,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _busy ? null : _signIn,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.login),
                          label: const Text('Google ile giriş yap',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
