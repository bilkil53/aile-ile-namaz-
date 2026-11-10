import 'package:aile_ile_namaz/privacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Hata metinlerinde hassas bilgi maskeleme', () {
    test('E-posta silinir', () {
      expect(scrubSensitive('Invalid login for ali.veli+test@gmail.com, statusCode: 400'),
          'Invalid login for [e-posta], statusCode: 400');
    });

    test('Oturum anahtarı (JWT) ve Bearer başlığı silinir', () {
      final s = scrubSensitive('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.abc_DEF-123');
      expect(s, isNot(contains('eyJ')));
      expect(s, contains('[token]'));
      expect(scrubSensitive('jwt eyJhbGciOiJIUzI1NiJ9 bitti'), 'jwt [token] bitti');
    });

    test('Adres ve gövdedeki gizli parametreler silinir', () {
      final s = scrubSensitive('{"access_token":"abc.def","refresh_token":"r3f","password": "gizli123"}');
      expect(s, isNot(contains('abc.def')));
      expect(s, isNot(contains('r3f')));
      expect(s, isNot(contains('gizli123')));
      expect(scrubSensitive('profiles?select=*&apikey=sb_publishable_abc123 hata'),
          'profiles?select=*&apikey=[gizli] hata');
      expect(scrubSensitive('callback?code=4/0AX4XfWh&state=xyz'), 'callback?code=[gizli]&state=xyz');
    });

    test('Kullanıcı kimliği (uuid) ve telefon silinir', () {
      expect(scrubSensitive('id=eq.0e76ede9-67b3-42b9-9090-c566ba0002d6 bulunamadı'), 'id=eq.[kimlik] bulunamadı');
      expect(scrubSensitive('Ara: 0532 123 45 67 ya da +905321234567'), 'Ara: [telefon] ya da [telefon]');
    });

    test('Ortak depolamadaki dosya adı silinir, klasör kalır', () {
      expect(scrubSensitive("path = '/storage/emulated/0/Download/Ali_kimlik.pdf' (OS Error)"),
          "path = '/storage/emulated/0/[dosya]' (OS Error)");
    });

    test('Uzun anahtar benzeri diziler (bildirim jetonu) silinir', () {
      expect(scrubSensitive('fcm dK3j:APA91bHPRgkF3JUikC4ENAHEeMrd41Zxv3hVZjC9KtT8OvPVGJ-hQMRKRrZuJAEcl7B6'),
          'fcm [gizli]');
    });

    test('Veritabanı satır ayrıntısındaki değerler (ad, dua metni) silinir', () {
      expect(
          scrubSensitive('new row violates check constraint "x" Failing row contains (12, Ayşe Yılmaz, Allah kabul etsin (dua), 2026-11-10).'),
          'new row violates check constraint "x" Failing row contains ([gizli]).');
      expect(scrubSensitive('Key (display_name)=(Erdinç Bilkil) already exists.'),
          'Key (display_name)=([gizli]) already exists.');
    });

    test('Uygulamanın telefondaki klasör yolu silinir', () {
      expect(scrubSensitive('FileSystemException: /data/user/0/com.bilkil53.aile_ile_namaz/app_flutter/a.json (OS Error)'),
          'FileSystemException: /data/user/0/[uygulama] (OS Error)');
      expect(scrubSensitive('open failed: /data/data/com.x/files/y'), 'open failed: /data/data/[uygulama]');
    });

    test('Hata ayıklama için gereken bilgi korunur', () {
      for (final t in [
        '#0      Repo.flushQueue (package:aile_ile_namaz/data.dart:445:11)',
        '#1      _rootRunUnary (dart:async/zone.dart:1415:47)',
        'PostgrestException(message: new row violates check constraint, code: 23514, details: null, hint: null)',
        "SocketException: Failed host lookup: 'tgshrnodnhmnofjhzpqp.supabase.co' (OS Error: errno = 7)",
        'RangeError (index): Invalid value: Not in inclusive range 0..4: 5',
        'build 3078 at 2026-11-08 23:45:10.123',
        '',
      ]) {
        expect(scrubSensitive(t), t, reason: t);
      }
    });
  });
}
