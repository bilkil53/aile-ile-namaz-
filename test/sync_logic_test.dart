import 'dart:async';
import 'dart:io';

import 'package:aile_ile_namaz/local_store.dart';
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

  group('Misafir kaza aktarımı', () {
    test('Sayılar sunucu biçimine çevrilir', () {
      expect(guestMergePayload({'FAJR': (3, 1), 'ISHA': (0, 0)}), {
        'FAJR': [3, 1],
        'ISHA': [0, 0],
      });
    });

    test('Boş veri boş gönderilir, negatif sayı gönderilmez', () {
      expect(guestMergePayload({}), isEmpty);
      expect(guestMergePayload({'FAJR': (-1, 0), 'ASR': (2, -3), 'DHUHR': (1, 1)}), {
        'DHUHR': [1, 1],
      });
    });

    test('Misafir verisi silinince sonucu bilinmeyen aktarım silinmez', () {
      addTearDown(() {
        LocalStore.pendingMerge = null;
        LocalStore.clearGuest();
      });
      LocalStore.pendingMerge = (id: 'g-1', user: 'u-1', items: {'FAJR': (2, 0)});
      LocalStore.guestKaza['ASR'] = (1, 0);
      LocalStore.clearGuest();
      expect(LocalStore.guestKaza, isEmpty);
      expect(LocalStore.pendingMerge?.id, 'g-1');
      expect(LocalStore.pendingMerge?.user, 'u-1');
      expect(LocalStore.pendingMerge?.items, {'FAJR': (2, 0)});
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
