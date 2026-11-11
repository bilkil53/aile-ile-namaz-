// Giriş yapılmış kullanıcı akışı: CI'da yalnızca TEST_EMAIL / TEST_PASSWORD gizli ayarları varsa çalışır.
// Test hesabı Supabase'de e-posta + şifreyle açılmış ayrı bir kullanıcıdır (Google hesabı şifresi değildir).
// Giriş, uygulamanın Google ekranı yerine doğrudan Supabase'e yapılır (Google otomatik girişi engeller).
//   flutter test integration_test/signed_in_test.dart --dart-define=UI_TEST=true \
//     --dart-define=TEST_EMAIL=... --dart-define=TEST_PASSWORD=... --dart-define=TEST_LANG=tr
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aile_ile_namaz/main.dart' as app;

const lang = String.fromEnvironment('TEST_LANG', defaultValue: 'tr');
const en = lang == 'en';
String L(String tr, String english) => en ? english : tr;
const email = String.fromEnvironment('TEST_EMAIL');
const password = String.fromEnvironment('TEST_PASSWORD');

Future<void> pumpUntil(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 45)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Ekranda bulunamadı ($timeout): $f');
}

Future<void> settle(WidgetTester t, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

void noErrorDialog(String where) {
  expect(find.text(L('Bir hata oluştu', 'An error occurred')), findsNothing, reason: '$where: uygulamada hata penceresi açıldı');
}

/// Açılışta çıkabilecek pencereleri (KVKK onayı, bildirim ayarı) kapatır; ana ekran görünene kadar.
Future<void> passStartupDialogs(WidgetTester t, Finder home) async {
  final kvkk = find.text(L('Kişisel verilerin korunması (KVKK)', 'Protection of personal data (KVKK)'));
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (kvkk.evaluate().isNotEmpty) {
      // İki kutuyu da işaretle, "Devam et"
      final boxes = find.descendant(of: find.byType(AlertDialog), matching: find.byType(Checkbox));
      for (final b in boxes.evaluate().toList()) {
        await t.tap(find.byWidget(b.widget));
        await settle(t, 2);
      }
      await t.tap(find.text(L('Devam et', 'Continue')));
      await settle(t, 6);
      continue;
    }
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      // Bildirim sağlığı vb. bilgi pencereleri: "Sonra" / "Kapat" / "Later" / "Close"
      for (final s in ['Sonra', 'Kapat', 'Tamam', 'Later', 'Close', 'OK']) {
        final b = find.descendant(of: find.byType(AlertDialog), matching: find.text(s));
        if (b.evaluate().isNotEmpty) {
          await t.tap(b.first);
          await settle(t, 4);
          break;
        }
      }
      continue;
    }
    if (home.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Giriş sonrası ana ekran açılmadı');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Giriş yapılmış kullanıcı ($lang): KVKK → Bugün işaretleme → 4 sekme → Ayarlar', (t) async {
    if (email.isEmpty || password.isEmpty) {
      markTestSkipped('TEST_EMAIL / TEST_PASSWORD verilmedi');
      return;
    }
    // Daha önce sorulmuş sayılan tek seferlik sorular (testi bekletmesin)
    SharedPreferences.setMockInitialValues({'lang': lang, 'askedLockScreen': true, 'notifyHealthAsked': true});
    await app.main();
    await settle(t, 4);

    final auth = Supabase.instance.client.auth;
    final res = await auth.signInWithPassword(email: email, password: password);
    expect(res.session, isNotNull, reason: 'Test hesabıyla giriş yapılamadı');

    final bar = find.byType(BottomNavigationBar);
    await passStartupDialogs(t, bar);
    noErrorDialog('Giriş sonrası');

    // 1) Bugün: vakit kartına dokun → giriş penceresi ÇIKMAMALI (giriş yapılmış kullanıcı)
    final todayList = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    await pumpUntil(t, todayList);
    final sabah = find.ancestor(of: find.text(L('Sabah', 'Fajr')), matching: find.byType(InkWell));
    await t.scrollUntilVisible(sabah, 200, scrollable: todayList.first, maxScrolls: 30);
    await t.ensureVisible(sabah.first);
    await settle(t, 4);
    await t.tap(sabah.first);
    await settle(t, 8);
    expect(find.text(L('Google Girişi Gerekir', 'Google Sign-in Required')), findsNothing,
        reason: 'Giriş yapılmış kullanıcıya giriş penceresi çıktı');
    noErrorDialog('Bugün işaretleme');

    // 2) Dört sekme açılıyor ve çökmüyor (giriş yapılmış hâlde sunucudan veri çekerek)
    for (final tab in en ? ['Family', 'Kaza', 'Report', 'Today'] : ['Aile Havuzu', 'Kaza', 'Karne', 'Bugün']) {
      final f = find.descendant(of: bar, matching: find.text(tab));
      await pumpUntil(t, f);
      await t.tap(f);
      await settle(t, 14);
      noErrorDialog('$tab sekmesi');
      expect(t.takeException(), isNull, reason: '$tab sekmesinde hata');
    }

    // 3) Ayarlar: giriş yapılmış kullanıcıya özel bölümler görünüyor
    await t.tap(find.byIcon(Icons.settings).first);
    await pumpUntil(t, find.text(L('Ayarlar', 'Settings')));
    final list = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last;
    final export = find.text(L('Verilerimi indir', 'Download my data'));
    await t.scrollUntilVisible(export, 300, scrollable: list, maxScrolls: 40);
    expect(export, findsOneWidget);
    noErrorDialog('Ayarlar');

    await auth.signOut();
    await settle(t, 6);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
