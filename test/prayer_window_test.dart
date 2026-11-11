import 'package:aile_ile_namaz/sync_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Namaz kaydı yalnızca İstanbul gününe göre -2..+1 gün yazılabilir', () {
    // 11 Kasım 2026, 10:00 İstanbul = 07:00 UTC
    final now = DateTime.utc(2026, 11, 11, 7);
    expect(isPrayerDateWritable('2026-11-11', now), isTrue);
    expect(isPrayerDateWritable('2026-11-10', now), isTrue);
    expect(isPrayerDateWritable('2026-11-09', now), isTrue);
    expect(isPrayerDateWritable('2026-11-12', now), isTrue);
    expect(isPrayerDateWritable('2026-11-08', now), isFalse);
    expect(isPrayerDateWritable('2026-11-13', now), isFalse);
    expect(isPrayerDateWritable('2021-01-01', now), isFalse);
    expect(isPrayerDateWritable('bozuk', now), isFalse);
  });

  test('İstanbul gece yarısı sınırı (UTC 21:00 = İstanbul ertesi gün 00:00)', () {
    final now = DateTime.utc(2026, 11, 10, 21, 30); // İstanbul 11 Kasım 00:30
    expect(isPrayerDateWritable('2026-11-09', now), isTrue);
    expect(isPrayerDateWritable('2026-11-08', now), isFalse);
  });
}
