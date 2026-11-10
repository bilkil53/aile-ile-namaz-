import 'dart:io';

import 'package:aile_ile_namaz/all_prayed.dart';
import 'package:aile_ile_namaz/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// "5 vaktin hepsini kıldı": yalnızca beş vaktin hepsi "Kıldı" ise tamam sayılır.
void main() {
  Map<String, PrayerStatus> all(PrayerStatus s) => {for (final k in prayerKeys) k: s};

  test('Beş vakit de kılındıysa tamam', () {
    expect(AllPrayed.isComplete(all(PrayerStatus.prayed)), isTrue);
  });

  test('Bir vakit eksik, kılınmadı ya da muafsa tamam değil', () {
    for (final other in [PrayerStatus.none, PrayerStatus.missed, PrayerStatus.excused]) {
      for (final k in prayerKeys) {
        final d = all(PrayerStatus.prayed)..[k] = other;
        expect(AllPrayed.isComplete(d), isFalse, reason: '$k = $other');
      }
    }
    expect(AllPrayed.isComplete({}), isFalse);
    expect(AllPrayed.isComplete(all(PrayerStatus.excused)), isFalse);
  });

  test('Aile bildirimi metni uygulama ile sunucuda aynı (TR ve EN)', () {
    final server = File('supabase/functions/push-family/index.ts').readAsStringSync();
    final app = File('lib/screens/home_shell.dart').readAsStringSync();
    for (final s in [
      '5 vaktin hepsini kıldı 🌟',
      'Maşallah! Günün bütün namazlarını eda etti. Allah kabul etsin.',
      'prayed all 5 prayers 🌟',
      "Completed all of the day's prayers. May Allah accept them.",
    ]) {
      expect(server, contains(s), reason: 'sunucu: $s');
      expect(app.replaceAll(r"\'", "'"), contains(s), reason: 'uygulama: $s');
    }
    // Sunucu kontrolü: uygulama bu olayı kendisi gönderemez (yalnızca tetikleyici üretir)
    final mig = File('supabase/migrations/20261110110000_37_all_prayed.sql').readAsStringSync();
    expect(mig, contains("new.isha = 'PRAYED'"));
    expect(mig, contains('on conflict do nothing'));
  });
}
