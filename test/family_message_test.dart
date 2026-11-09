import 'dart:convert';
import 'dart:io';

import 'package:aile_ile_namaz/content/daily_content.dart';
import 'package:aile_ile_namaz/content/family_message.dart';
import 'package:aile_ile_namaz/dini_gunler.dart';
import 'package:aile_ile_namaz/lang.dart';
import 'package:aile_ile_namaz/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hazır aile mesajları her zaman Türkçe gönderilir, alıcı kendi dilinde görür.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'lang': 'tr'});
    await AppSettings.init();
  });

  test('Gönderilen tebrik metni dil İngilizceyken de Türkçedir', () async {
    await Lang.set(AppLang.en);
    for (final g in greetings) {
      expect(g.textTr, isNot(g.text), reason: 'İngilizcede ekranda İngilizce görünür');
      expect(familyMessagesEn.containsKey(g.textTr), isTrue);
    }
    final bayramlar = diniGunler.where((d) => d.bayram).toList();
    expect(bayramlar, hasLength(2));
    for (final d in bayramlar) {
      expect(bayramMessageTr(d), contains(d.nameTr));
      expect(bayramMessageEn(d), contains(d.nameEn));
    }
  });

  test('Alıcı kendi dilinde görür; kendi yazılmış mesaj değişmez', () async {
    final tr = greetings.first.textTr;
    await Lang.set(AppLang.en);
    expect(familyMessageText(tr), greetings.first.textEn);
    expect(familyMessageText('Kendi duam'), 'Kendi duam');
    await Lang.set(AppLang.tr);
    expect(familyMessageText(tr), tr);
    // 1.78'den İngilizce gönderilmiş tebrik Türkçe alıcıda Türkçe görünür
    expect(familyMessageText(greetings.first.textEn), tr);
    for (final m in ['constructor', '__proto__', 'toString', '']) {
      expect(familyMessageText(m), m);
    }
  });

  test('Sunucudaki (push-family) İngilizce liste uygulamayla aynı', () {
    final src = File('supabase/functions/push-family/index.ts').readAsStringSync();
    final start = src.indexOf('const GREET_EN');
    expect(start, greaterThanOrEqualTo(0), reason: 'push-family içinde GREET_EN yok');
    final block = src.substring(start, src.indexOf('};', start));
    for (final e in familyMessagesEn.entries) {
      expect(block.contains('${jsonEncode(e.key)}: ${jsonEncode(e.value)}'), isTrue,
          reason: 'push-family GREET_EN eksik/farklı: ${e.key}');
    }
    final count = RegExp(r'^\s+"', multiLine: true).allMatches(block).length;
    expect(count, familyMessagesEn.length, reason: 'sunucuda fazladan ya da eski metin var');
  });
}
