// Emülatörde gerçek uygulamayı açıp misafir (gezinti) akışını parmakla dokunur gibi dener.
// CI'da çalışır: flutter test integration_test/app_test.dart --dart-define=UI_TEST=true
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Misafir akışı: hoş geldin → gezinti → işaretleme engeli → 4 sekme', (t) async {
    await app.main();

    // 1) Hoş geldin penceresi → "Giriş Yapmadan Devam Et" (alttaki buton)
    final guestBtn = find.text('Giriş Yapmadan Devam Et');
    await pumpUntil(t, guestBtn);
    await t.ensureVisible(guestBtn.last);
    await settle(t, 3);
    await t.tap(guestBtn.last);
    await settle(t);

    // 2) Açıklama penceresi → "Gezintiye Başla"
    final start = find.text('Gezintiye Başla');
    await pumpUntil(t, start);
    await t.tap(start);
    await settle(t, 12);

    // 3) Bugün ekranı: vakit kartına dokun → misafir kayıt yapamaz (giriş penceresi)
    //    ya da vakit henüz girmediyse "… girecek" bilgisi çıkar. İkisi de doğru davranış.
    // Kartlar listenin aşağısında: liste kaydırılarak karta gelinir (ekran dışındakiler henüz çizilmez)
    final todayList = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    await pumpUntil(t, todayList);
    // Yalnızca vakit kartındaki "Sabah" (üstteki özet kartında da geçebilir)
    final sabah = find.ancestor(of: find.text('Sabah'), matching: find.byType(InkWell));
    // Not: .first boşken hata verir; kaydırma sırasında süzgeçsiz bulucu verilir
    await t.scrollUntilVisible(sabah, 200, scrollable: todayList.first, maxScrolls: 30);
    await t.ensureVisible(sabah.first);
    await settle(t, 4);
    await t.tap(sabah.first);
    final loginDlg = find.text('Google Girişi Gerekir');
    final notYet = find.textContaining('girecek');
    final seen = await pumpUntilAny(t, [loginDlg, notYet]);
    if (seen == loginDlg) {
      await t.tap(find.text('Gezinmeye Devam'));
      await settle(t);
      expect(loginDlg, findsNothing);
    }

    // 4) Dört sekmenin hepsi açılıyor ve çökmüyor
    for (final tab in ['Aile Havuzu', 'Kaza', 'Karne', 'Bugün']) {
      final f = find.descendant(of: find.byType(BottomNavigationBar), matching: find.text(tab));
      await pumpUntil(t, f);
      await t.tap(f);
      await settle(t, 10);
      expect(t.takeException(), isNull, reason: '$tab sekmesinde hata');
    }
    await pumpUntil(t, todayList); // Bugün'e geri dönüldü, liste yine görünüyor
  }, timeout: const Timeout(Duration(minutes: 8)));
}
