import 'package:aile_ile_namaz/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Namaz durumu kodları geri dönüşümlü', () {
    for (final s in PrayerStatus.values) {
      expect(PrayerStatusX.parse(s.code), s);
    }
  });
}
