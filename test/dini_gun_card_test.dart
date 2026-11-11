import 'dart:convert';

import 'package:aile_ile_namaz/dini_gunler.dart';
import 'package:aile_ile_namaz/lang.dart';
import 'package:aile_ile_namaz/settings.dart';
import 'package:aile_ile_namaz/widgets/dini_gun_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ekran testi: "yarın" bilgi kartının etiketi ve kart sırası (bayram > bugün > yarın).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DiniGun gun(String k) => diniGunler.firstWhere((g) => g.key == k);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime plus(int d) => DateTime(today.year, today.month, today.day + d);
  // Uzak bir gün: liste "kısa" sayılıp internetten yenilenmeye çalışılmasın
  final far = DiniGunEvent(gun('asure'), plus(300));

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'diniGunler.v1': jsonEncode({'at': today.toIso8601String(), 'events': []}),
    });
    await AppSettings.init();
    await Lang.set(AppLang.tr); // test ortamının dili İngilizce: Türkçe metinler sınanıyor
  });
  tearDown(() => DiniGunler.setEventsForTest([]));

  Future<void> show(WidgetTester t, List<DiniGunEvent> events) async {
    DiniGunler.setEventsForTest([...events, far]);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DiniGunCard()))));
    await t.pump();
  }

  testWidgets('Kandilden 1 gün önce: "Yarın akşam" kartı, anlam ve önemi ile', (t) async {
    await show(t, [DiniGunEvent(gun('mirac'), plus(1))]);
    expect(find.text('Miraç Kandili'), findsOneWidget);
    expect(find.text('Yarın akşam'), findsOneWidget);
    expect(find.text('Anlamı ve önemi'), findsOneWidget);
    expect(find.textContaining('diyanet.gov.tr'), findsOneWidget);
  });

  testWidgets('2 gün kala kart görünmez', (t) async {
    await show(t, [DiniGunEvent(gun('mirac'), plus(2))]);
    expect(find.text('Miraç Kandili'), findsNothing);
    expect(find.text('Yarın akşam'), findsNothing);
  });

  testWidgets('Arefe günü: arefe kartının altında "Yarın" bayram kartı', (t) async {
    await show(t, [DiniGunEvent(gun('ramazan_arefe'), today), DiniGunEvent(gun('ramazan_bayrami'), plus(1))]);
    expect(find.textContaining('Arefe'), findsWidgets);
    expect(find.text('Yarın'), findsOneWidget);
    expect(find.text('Ramazan Bayramı'), findsOneWidget);
  });

  testWidgets('Bayram günü yalnızca bayram kartı: "yarın" kartı çıkmaz', (t) async {
    await show(t, [DiniGunEvent(gun('ramazan_bayrami'), today), DiniGunEvent(gun('mirac'), plus(1))]);
    expect(find.text('Yarın akşam'), findsNothing);
    expect(find.text('Anlamı ve önemi'), findsNothing);
  });

  testWidgets('Önizleme: takvim boşken de 1 gün önce ve o gün kartı çizilir', (t) async {
    DiniGunler.setEventsForTest([]);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: Column(children: [
      DiniGunCard(preview: gun('mirac'), previewTomorrow: true),
      DiniGunCard(preview: gun('mirac')),
    ])))));
    await t.pump();
    expect(find.text('Yarın akşam'), findsOneWidget);
    expect(find.textContaining('Miraç Kandili'), findsWidgets);
    expect(find.text('Anlamı ve önemi'), findsOneWidget);
  });
}
