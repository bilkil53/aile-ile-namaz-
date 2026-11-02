import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../local_store.dart';
import '../theme.dart';

/// İlk açılışta uygulamanın üzerinde çıkan "Hoş Geldiniz" penceresi.
/// Dönüş: true = Google ile giriş yapıldı, false = giriş yapmadan devam edildi.
Future<bool> showWelcome(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => const PopScope(canPop: false, child: WelcomeDialog()),
  );
  return r ?? false;
}

class WelcomeDialog extends StatefulWidget {
  const WelcomeDialog({super.key});

  @override
  State<WelcomeDialog> createState() => _WelcomeDialogState();
}

class _WelcomeDialogState extends State<WelcomeDialog> {
  bool _busy = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // Tarayıcıyla girişten dönülünce pencereyi kapat.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.session != null && mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(true);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  final _google = GoogleSignIn(
    serverClientId: AppConfig.googleWebClientId,
    scopes: const ['email', 'profile'],
  );

  /// 1) Telefondaki Google hesaplarından seçtirir (tarayıcı açılmaz).
  /// 2) Bu yol çalışmazsa (ör. Google Play Hizmetleri yok) tarayıcı girişine düşer.
  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      final ok = await _nativeSignIn();
      if (!ok) return; // hesap seçimini kapattı → pencere açık kalır
      await LocalStore.setGuestMode(false);
    } catch (_) {
      try {
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: AppConfig.authRedirect,
          queryParams: {'prompt': 'select_account'},
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Giriş yapılamadı. Lütfen tekrar deneyin.')));
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _nativeSignIn() async {
    await _google.signOut(); // her seferinde hesap listesi gelsin
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

  /// "Giriş yapmadan devam et" → ne olacağını açıklayan küçük onay penceresi.
  Future<void> _guest() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(color: AppColors.goldContainer, shape: BoxShape.circle),
          child: const Icon(Icons.phone_android, color: AppColors.gold, size: 28),
        ),
        title: const Text('Giriş Yapmadan Devam Et', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: const Column(mainAxisSize: MainAxisSize.min, children: [
          _Bullet('👀', 'Uygulamayı serbestçe gezip tüm ekranları deneyebilirsin.'),
          _Bullet('⏳', 'İşaretlediklerin sadece bu oturumda tutulur; uygulama kapanınca silinir.'),
          _Bullet('👨‍👩‍👧', 'Aile Havuzunda gerçek bağlantı ve aile bildirimleri için giriş gerekir.'),
          _Bullet('☁️', 'Giriş yaparsan bu oturumda yaptıkların buluta kaydedilir.'),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Google ile Giriş Yap')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.emerald),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gezintiye Başla'),
          ),
        ],
      ),
    );
    if (go == null || !mounted) return;
    if (go) {
      await LocalStore.setGuestMode(true);
      if (mounted) Navigator.of(context).pop(false);
    } else {
      await _signIn();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: AppColors.emeraldContainer, shape: BoxShape.circle),
            child: const Icon(Icons.mosque, size: 42, color: AppColors.emerald),
          ),
          const SizedBox(height: 16),
          const Text("Aile ile Namaz'a Hoş Geldiniz",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('Birlikte namaz kılın, kaza borçlarınızı takip edin ve ortak ibadet havuzunda buluşun 🤲',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35)),
          const SizedBox(height: 12),
          const _Feature(
            icon: Icons.home,
            bg: AppColors.emeraldContainer,
            fg: AppColors.emerald,
            title: 'Bugün Sekmesi (Vakitler & Kıble)',
            text: 'Diyanet uyumlu vakitler, 5 vakit namaz takibi ve canlı kıble pusulası.',
          ),
          const _Feature(
            icon: Icons.groups,
            bg: Color(0xFFE0F2FE),
            fg: Color(0xFF0369A1),
            title: 'Aile Havuzu (İbadet Halkası)',
            text: 'Eşiniz ve çocuklarınızla tek davet kodu ile bağlanın; namaz durumlarını birlikte görün.',
          ),
          const _Feature(
            icon: Icons.calendar_month,
            bg: Color(0xFFFFEDD5),
            fg: Color(0xFFEA580C),
            title: 'Kaza (Mahremiyet Korumalı)',
            text: 'Kaza borçlarınızı tutun; ailenizin kaza durumunu sadece özet olarak görün.',
          ),
          const _Feature(
            icon: Icons.emoji_events,
            bg: Color(0xFFF3E8FF),
            fg: Color(0xFF7E22CE),
            title: 'Karne (İstatistik & Motivasyon)',
            text: 'Haftalık başarı oranınız, manevi rozetler ve günün hadisi.',
          ),
          const SizedBox(height: 8),
          Material(
            color: AppColors.emerald,
            borderRadius: BorderRadius.circular(22),
            elevation: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _busy ? null : _signIn,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: _busy
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('G',
                            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Color(0xFF4285F4))),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Google ile Hızlı Giriş Yap',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                      SizedBox(height: 2),
                      Text('Kayıtların buluta yedeklenir, ailenle eşitlenir',
                          style: TextStyle(fontSize: 11, color: Colors.white70)),
                    ]),
                  ),
                  const Icon(Icons.arrow_forward, color: Colors.white),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _busy ? null : _guest,
            child: const Text('Giriş Yapmadan Devam Et',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
        ]),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final Color bg, fg;
  final String title, text;
  const _Feature({required this.icon, required this.bg, required this.fg, required this.title, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3)),
            ]),
          ),
        ]),
      );
}

class _Bullet extends StatelessWidget {
  final String emoji, text;
  const _Bullet(this.emoji, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.35))),
        ]),
      );
}
