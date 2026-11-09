import 'package:aile_ile_namaz/content/approaching_quotes.dart';
import 'package:aile_ile_namaz/content/content_en.dart';
import 'package:aile_ile_namaz/content/daily_content.dart';
import 'package:aile_ile_namaz/cuma_reminder.dart';
import 'package:aile_ile_namaz/dini_gunler.dart';
import 'package:aile_ile_namaz/lang.dart';
import 'package:aile_ile_namaz/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Onaylanan dini metinlerin İngilizcesi eksiksiz bağlı mı? (Türkçe metin değişirse test yakalar)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'lang': 'tr'});
    await AppSettings.init();
  });

  final quotes = <DailyQuote>[
    ...ayetler, ...hadisler, ...dualar, ...motivasyonlar, ...ozluSozler,
    for (final l in approachingQuotes.values) ...l,
  ];

  test('Her ayet / hadis / dua / hatırlatmanın İngilizcesi var', () {
    final missing = <String>[
      for (final q in quotes)
        for (final s in [q.category, q.title, q.text, q.source])
          if (!contentEn.containsKey(s)) s,
    ];
    expect(missing, isEmpty);
  });

  test('Hazır tebriklerin İngilizcesi var', () {
    final missing = <String>[
      for (final g in greetings)
        for (final s in [g.title, g.category, g.text])
          if (!contentEn.containsKey(s)) s,
    ];
    expect(missing, isEmpty);
  });

  test('Cuma hatırlatma hadislerinin İngilizcesi var', () {
    final missing = <String>[
      for (final (h, k) in CumaReminder.textsForTest)
        for (final s in [h, k])
          if (!contentEn.containsKey(s)) s,
    ];
    expect(missing, isEmpty);
  });

  test('Mübarek gün adları ve açıklamaları İngilizcede Türkçe kalmaz', () async {
    final tr = {for (final g in diniGunler) g.key: (g.name, g.meaning)};
    await Lang.set(AppLang.en);
    for (final g in diniGunler) {
      expect(g.name, isNot(tr[g.key]!.$1), reason: g.key);
      expect(g.meaning, isNot(tr[g.key]!.$2), reason: g.key);
    }
  });

  test('Dil İngilizceyken içerik İngilizce, Türkçeyken Türkçe', () async {
    final q = ayetler.first;
    final trText = q.text;
    await Lang.set(AppLang.en);
    expect(q.text, contentEn[trText]);
    await Lang.set(AppLang.tr);
    expect(q.text, trText);
  });
}
