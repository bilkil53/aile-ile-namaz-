import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: AppConfig.authRedirect,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giriş yapılamadı. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
