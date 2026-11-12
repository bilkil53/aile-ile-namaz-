import 'package:aile_ile_namaz/prayer_times.dart';
import 'package:aile_ile_namaz/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Vakit servisine giden koordinat yaklaşık 1 km\'ye yuvarlanır', () {
    expect(PrayerTimesService.coord(41.0082374), '41.01');
    expect(PrayerTimesService.coord(28.9783589), '28.98');
    expect(PrayerTimesService.coord(-33.86881), '-33.87');
  });

  test('Yerel vakit hesabı: vakitler sıralı ve makul (İstanbul, yaz ve kış)', () {
    for (final day in [DateTime(2026, 6, 21), DateTime(2026, 12, 21), DateTime(2026, 3, 20)]) {
      final t = PrayerTimesService.calculate(day, 41.0082, 28.9784);
      final list = [t.imsak, t.gunes, t.ogle, t.ikindi, t.aksam, t.yatsi];
      for (final v in list) {
        expect(RegExp(r'^\d{2}:\d{2}$').hasMatch(v), isTrue, reason: v);
      }
      final sorted = [...list]..sort();
      expect(list, sorted, reason: 'vakitler sırayla artmalı: $list');
      expect(t.ogle.compareTo('12:30') > 0 && t.ogle.compareTo('13:40') < 0, isTrue, reason: 'öğle ${t.ogle}');
    }
  });

  test('En düşük sürüm ayarı: bozuk ya da eksik veri zorlamaz', () {
    expect(UpdateChecker.parseMinBuild('{"min_build": 101}'), 101);
    expect(UpdateChecker.parseMinBuild('{"min_build": "101"}'), 0);
    expect(UpdateChecker.parseMinBuild('{"min_build": -5}'), 0);
    expect(UpdateChecker.parseMinBuild('{}'), 0);
    expect(UpdateChecker.parseMinBuild('<html>404</html>'), 0);
    expect(UpdateChecker.parseMinBuild(''), 0);
  });

  test('Yayın etiketinden derleme numarası: v1.0.N → N + 1, eski r etiketleri yok sayılır', () {
    expect(UpdateChecker.buildOfTag('v1.0.0'), 1);
    expect(UpdateChecker.buildOfTag('v1.0.1-demo'), 2);
    expect(UpdateChecker.buildOfTag('v1.2.57'), 58);
    expect(UpdateChecker.buildOfTag('r105'), 0);
    expect(UpdateChecker.buildOfTag('v1.93'), 0);
    expect(UpdateChecker.buildOfTag(''), 0);
    expect(UpdateChecker.buildOfTag('v1.0.0-beta'), 0);
  });

  test('İndirme adresi görülen yayın etiketine sabitlenir; etiket yoksa "en son" adresi', () {
    expect(UpdateChecker.assetBase('v1.0.17'), endsWith('/releases/download/v1.0.17'));
    expect(UpdateChecker.assetBase(''), endsWith('/releases/latest/download'));
    expect(UpdateChecker.assetBase('r105'), endsWith('/releases/latest/download'));
    expect(UpdateChecker.assetBase('../kötü'), endsWith('/releases/latest/download'));
  });
}
