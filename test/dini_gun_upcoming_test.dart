import 'package:aile_ile_namaz/dini_gunler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mirac = diniGunler.firstWhere((g) => g.key == 'mirac');
  final berat = diniGunler.firstWhere((g) => g.key == 'berat');

  test('Yaklaşan mübarek gün: 7 gün kala açılır, her gün sayar, o gün sayılmaz', () {
    DiniGunler.setEventsForTest([DiniGunEvent(berat, DateTime(2027, 1, 24)), DiniGunEvent(mirac, DateTime(2027, 1, 5))]);
    expect(DiniGunler.upcoming(DateTime(2026, 12, 28)), isNull, reason: '8 gün kala henüz yok');
    expect(DiniGunler.upcoming(DateTime(2026, 12, 29, 23, 30))?.$2, 7);
    expect(DiniGunler.upcoming(DateTime(2027, 1, 2))?.$2, 3);
    expect(DiniGunler.upcoming(DateTime(2027, 1, 4))?.$1.key, 'mirac');
    expect(DiniGunler.upcoming(DateTime(2027, 1, 4))?.$2, 1);
    expect(DiniGunler.upcoming(DateTime(2027, 1, 5)), isNull, reason: 'o gün bugünkü kart gösterilir');
    expect(DiniGunler.upcoming(DateTime(2027, 1, 18))?.$1.key, 'berat');
    DiniGunler.setEventsForTest([]);
    expect(DiniGunler.upcoming(DateTime(2027, 1, 1)), isNull);
  });
}
