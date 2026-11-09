// Emülatörde gerçek uygulamayı açıp misafir (gezinti) akışını parmakla dokunur gibi dener.
// CI'da çalışır: flutter test integration_test/app_test.dart --dart-define=UI_TEST=true
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aile_ile_namaz/main.dart' as app;

/// pumpAndSettle dönen yükleme göstergesinde takılır; bunun yerine bulunana kadar kare kare bekler.
Future<void> pumpUntil(WidgetTester t, Finder f, {Duration timeout = const Duration(seconds: 40)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Ekranda bulunamadı ($timeout): $f');
}

/// İki ihtimalden biri görünene kadar bekler; hangisi göründüyse onu döndürür.
Future<Finder> pumpUntilAny(WidgetTester t, List<Finder> fs, {Duration timeout = const Duration(seconds: 15)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 250));
    for (final f in fs) {
      if (f.evaluate().isNotEmpty) return f;
    }
  }
  throw TestFailure('Beklenenlerin hiçbiri görünmedi ($timeout): $fs');
}

Future<void> settle(WidgetTester t, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

/// Uygulamanın kendi hata penceresi açıldıysa test o adımda net bir sebeple durur.
void noErrorDialog(String where) {
  expect(find.text(L('Bir hata oluştu', 'An error occurred')), findsNothing, reason: '$where: uygulamada hata penceresi açıldı');
}

/// CI testi iki kez çalıştırır: --dart-define=TEST_LANG=tr ve =en
const lang = String.fromEnvironment('TEST_LANG', defaultValue: 'tr');
const en = lang == 'en';
String L(String tr, String english) => en ? english : tr;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Misafir akışı ($lang): hoş geldin → gezinti → işaretleme engeli → 4 sekme', (t) async {
    // Uygulama dili test diline sabitlenir (telefon dili ne olursa olsun)
    SharedPreferences.setMockInitialValues({'lang': lang});
    await app.main();

    // 1) Hoş geldin penceresi → "Giriş Yapmadan Devam Et" (alttaki buton)
    final guestBtn = find.text(L('Giriş Yapmadan Devam Et', 'Continue Without Signing In'));
    await pumpUntil(t, guestBtn);
    await t.ensureVisible(guestBtn.last);
    await settle(t, 3);
    await t.tap(guestBtn.last);
    await settle(t);

    // 2) Açıklama penceresi → "Gezintiye Başla"
    final start = find.text(L('Gezintiye Başla', 'Start Browsing'));
    await pumpUntil(t, start);
    await t.tap(start);
    await settle(t, 12);

    // 3) Bugün ekranı: vakit kartına dokun → misafir kayıt yapamaz (giriş penceresi)
    //    ya da vakit henüz girmediyse "… girecek" bilgisi çıkar. İkisi de doğru davranış.
    // Kartlar listenin aşağısında: liste kaydırılarak karta gelinir (ekran dışındakiler henüz çizilmez)
    final todayList = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    await pumpUntil(t, todayList);
    // Yalnızca vakit kartındaki "Sabah" (üstteki özet kartında da geçebilir)
    final sabah = find.ancestor(of: find.text(L('Sabah', 'Fajr')), matching: find.byType(InkWell));
    // Not: .first boşken hata verir; kaydırma sırasında süzgeçsiz bulucu verilir
    await t.scrollUntilVisible(sabah, 200, scrollable: todayList.first, maxScrolls: 30);
    await t.ensureVisible(sabah.first);
    await settle(t, 4);
    noErrorDialog('Bugün ekranı');
    await t.tap(sabah.first);
    final loginDlg = find.text(L('Google Girişi Gerekir', 'Google Sign-in Required'));
    final notYet = find.textContaining(L('girecek', 'starts at'));
    final seen = await pumpUntilAny(t, [loginDlg, notYet]);
    if (seen == loginDlg) {
      await t.tap(find.text(L('Gezinmeye Devam', 'Keep Browsing')));
      await settle(t);
      expect(loginDlg, findsNothing);
    }

    // 4) Dört sekmenin hepsi açılıyor ve çökmüyor
    for (final tab in en ? ['Family', 'Kaza', 'Report', 'Today'] : ['Aile Havuzu', 'Kaza', 'Karne', 'Bugün']) {
      final f = find.descendant(of: find.byType(BottomNavigationBar), matching: find.text(tab));
      await pumpUntil(t, f);
      await t.tap(f);
      await settle(t, 10);
      noErrorDialog('$tab sekmesi');
      expect(t.takeException(), isNull, reason: '$tab sekmesinde hata');
    }
    await pumpUntil(t, todayList); // Bugün'e geri dönüldü, liste yine görünüyor
  }, timeout: const Timeout(Duration(minutes: 8)));
}
