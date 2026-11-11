import 'package:aile_ile_namaz/notifications.dart';
import 'package:aile_ile_namaz/prayer_times.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Yeniden kurarken yalnızca hatırlatma kimlikleri iptal edilir', () {
    for (final id in [1, 50, 99, 100, 109, 199, 300, 345, 399]) {
      expect(Notifications.isManagedId(id), isTrue, reason: '$id');
    }
    // 900: "5 vaktin hepsini kıldın"; 9100+: rozet; 0 / büyük sayılar: aile bildirimi; 200–299 ayrılmış değil
    for (final id in [0, 200, 299, 400, 900, 9100, 123456]) {
      expect(Notifications.isManagedId(id), isFalse, reason: '$id');
    }
  });

  test('Vakit saati doğrulaması: bozuk değer alarm planına girmez', () {
    for (final v in ['05:12', '00:00', '23:59', '12:30']) {
      expect(DayTimes.validTime(v), isTrue, reason: v);
    }
    for (final v in ['', '5:12', '24:00', '12:60', '12:3', 'ab:cd', '05:12 (+03)', '0512']) {
      expect(DayTimes.validTime(v), isFalse, reason: v);
    }
    DayTimes d(String imsak) => DayTimes(
        date: DateTime(2026, 11, 11), imsak: imsak, gunes: '07:10', ogle: '12:50', ikindi: '15:30', aksam: '17:50', yatsi: '19:10', fromDiyanet: true);
    expect(d('05:40').isValid, isTrue);
    expect(d('xx').isValid, isFalse);
  });
}
