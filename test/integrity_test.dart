import 'package:aile_ile_namaz/integrity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = '037c720a61ab299f7daf8915b8425da3eee339c7b3aabe6384c0d590e1750d7f';
  const b = 'aaaa0000bbbb1111cccc2222dddd3333eeee4444ffff5555aaaa6666bbbb7777';

  group('İmza kontrolü (fail-closed)', () {
    test('Beklenen imza tutarsa açılır', () {
      expect(Integrity.verdict(signature: a, expected: a, store: 'github'), IntegrityVerdict.ok);
      expect(Integrity.verdict(signature: a.toUpperCase(), expected: ' $a ', store: 'github'), IntegrityVerdict.ok);
      expect(Integrity.verdict(signature: b, expected: '$a,$b', store: 'github'), IntegrityVerdict.ok);
    });

    test('Anahtar yenilendiyse imza geçmişindeki herhangi bir sertifika yeterli', () {
      expect(Integrity.verdict(signature: '$b,$a', expected: a, store: 'github'), IntegrityVerdict.ok);
      expect(Integrity.verdict(signature: '$a, $b', expected: b, store: 'github'), IntegrityVerdict.ok);
      expect(Integrity.verdict(signature: '$b,', expected: a, store: 'github'), IntegrityVerdict.block);
    });

    test('İmza tutmazsa açılmaz', () {
      expect(Integrity.verdict(signature: b, expected: a, store: 'github'), IntegrityVerdict.block);
    });

    test('İmza okunamazsa sessizce geçilmez, açılmaz', () {
      expect(Integrity.verdict(signature: null, expected: a, store: 'github'), IntegrityVerdict.block);
      expect(Integrity.verdict(signature: '', expected: a, store: 'github'), IntegrityVerdict.block);
      expect(Integrity.verdict(signature: '  ', expected: a, store: 'github'), IntegrityVerdict.block);
    });

    test('Google Play sürümünde uygulama içi kontrol yapılmaz (Play yeniden imzalar)', () {
      expect(Integrity.verdict(signature: b, expected: a, store: 'play'), IntegrityVerdict.skip);
      expect(Integrity.verdict(signature: null, expected: a, store: 'play'), IntegrityVerdict.skip);
    });

    test('Beklenen imza gömülmemiş yerel derlemede kontrol yapılmaz', () {
      expect(Integrity.verdict(signature: b, expected: '', store: 'github'), IntegrityVerdict.skip);
      expect(Integrity.verdict(signature: b, expected: ' , ', store: 'github'), IntegrityVerdict.skip);
    });
  });
}
