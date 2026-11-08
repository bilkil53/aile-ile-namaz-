import 'dart:async';
import 'dart:io';

import 'package:aile_ile_namaz/local_store.dart';
import 'package:aile_ile_namaz/models.dart';
import 'package:aile_ile_namaz/sync_logic.dart';
import 'package:aile_ile_namaz/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

PostgrestException pg(String? code) => PostgrestException(message: 'test', code: code);

void main() {
  group('Gönderim hatası ayrımı (kalıcı ret mi, geçici mi)', () {
    test('Kural/kısıt/geçersiz veri/tetikleyici hataları kalıcı ret sayılır', () {
      for (final c in ['23514', '23505', '42703', '22P02', '22023', 'P0001']) {
        expect(classifySyncError(pg(c)), SyncFailure.rejected, reason: c);
      }
    });

    test('Bağlantı, zaman aşımı ve geçici sunucu hataları tekrar denenir', () {
      // 42501: oturum düşmüşse yetki hatası gelir; kayıt hemen silinmemeli.
      // 429/422/500: JSON olmayan cevapta kütüphane HTTP durumunu koda yazar; kalıcı ret değildir.
      for (final c in ['42501', '28000', 'PGRST301', 'PGRST000', '57014', '53300', '08006', '40001',
          '429', '422', '500', '4290', '42', null, '']) {
        expect(classifySyncError(pg(c)), SyncFailure.temporary, reason: '$c');
      }
      expect(classifySyncError(const SocketException('internet yok')), SyncFailure.temporary);
      expect(classifySyncError(TimeoutException('yavaş')), SyncFailure.temporary);
      expect(classifySyncError(Exception('bilinmeyen')), SyncFailure.temporary);
    });

    test('Yetki hatası ayrıca tanınır (birkaç denemeden sonra kalıcı sayılır)', () {
      expect(isAuthError(pg('42501')), isTrue);
      expect(isAuthError(pg('23514')), isFalse);
      expect(isAuthError(const SocketException('yok')), isFalse);
      expect(maxAuthRetries, greaterThan(1));
    });
  });

  group('Kuyruk kaydı eşleştirme', () {
    test('Aynı vakit ve aynı durum aynı işlemdir; deneme sayacı fark etmez', () {
      final a = <String, dynamic>{'t': 'prayer', 'date': '2026-11-08', 'key': 'fajr', 'status': 'PRAYED'};
      expect(sameQueueOp(a, {...a}), isTrue);
      expect(sameQueueOp(a, {...a, 'a': 3}), isTrue);
    });

    test('Gönderim sürerken yeniden işaretlenen vakit eski işlemle karışmaz', () {
      final eski = <String, dynamic>{'t': 'prayer', 'date': '2026-11-08', 'key': 'fajr', 'status': 'PRAYED'};
      expect(sameQueueOp(eski, {...eski, 'status': 'MISSED'}), isFalse);
      expect(sameQueueOp(eski, {...eski, 'key': 'isha'}), isFalse);
      expect(sameQueueOp(eski, {...eski, 'date': '2026-11-07'}), isFalse);
    });

    test('Kaza kayıtları tür ve sayılarla eşleşir', () {
      final k = <String, dynamic>{'t': 'kaza', 'type': 'FAJR', 'o': 3, 'c': 1};
      expect(sameQueueOp(k, {...k}), isTrue);
      expect(sameQueueOp(k, {...k, 'c': 2}), isFalse);
      expect(sameQueueOp(k, {'t': 'prayer', 'type': 'FAJR', 'o': 3, 'c': 1}), isFalse);
      expect(sameQueueOp({'t': 'x'}, {'t': 'x'}), isFalse);
    });
  });

  group('Kaza gönderimi', () {
    test('Kuyruktaki ilgili türün en son kaydı seçilir', () {
      final q = <Map<String, dynamic>>[
        {'t': 'kaza', 'type': 'FAJR', 'o': 3, 'c': 0},
        {'t': 'prayer', 'date': '2026-11-08', 'key': 'fajr', 'status': 'PRAYED'},
        {'t': 'kaza', 'type': 'ASR', 'o': 1, 'c': 0},
        {'t': 'kaza', 'type': 'FAJR', 'o': 3, 'c': 2},
      ];
      expect(latestKazaOp(q, 'FAJR'), {'t': 'kaza', 'type': 'FAJR', 'o': 3, 'c': 2});
      expect(latestKazaOp(q, 'ASR')?['o'], 1);
      expect(latestKazaOp(q, 'ISHA'), isNull);
      expect(latestKazaOp([], 'FAJR'), isNull);
    });
  });

  group('Gezinti (misafir) modu', () {
    test('Giriş yokken telefona kalıcı kayıt yapılmaz; gezintiye girince bellek boşaltılır', () async {
      // Testte Supabase başlatılmadı: LocalStore "giriş yok" sayar ve yalnızca belleğe yazar
      await LocalStore.saveKaza('FAJR', 2, 0);
      await LocalStore.setPrayer('2026-11-08', 'fajr', PrayerStatus.prayed);
      await LocalStore.setGuestMode(true);
      addTearDown(() => LocalStore.setGuestMode(false));
      expect(LocalStore.kaza(), isEmpty);
      expect(LocalStore.day('2026-11-08'), isEmpty);
    });
  });

  group('Güncelleme derleme numarası', () {
    test('İşlemci türüne göre sürüm kodundan derleme numarası çıkarılır', () {
      expect(UpdateChecker.buildOf('3074'), 74);
      expect(UpdateChecker.buildOf('1052'), 52);
      expect(UpdateChecker.buildOf('74'), 74);
      expect(UpdateChecker.buildOf(''), 0);
      expect(UpdateChecker.buildOf('abc'), 0);
    });
  });
}
