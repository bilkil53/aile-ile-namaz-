import 'dart:convert';

import 'package:aile_ile_namaz/data_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dosya içeriği: bütün bölümler var, eksikler belirtilir, JSON olarak yazılabilir', () {
    final m = DataExport.build(
      uid: 'u1',
      email: null,
      at: DateTime.utc(2026, 11, 11, 9),
      appVersion: '1.0.2',
      data: {
        'namaz_kayitlari': [
          {'prayer_date': '2026-11-10', 'fajr': 'PRAYED'}
        ],
      },
      missing: ['cihazlar'],
    );
    for (final t in DataExport.tables) {
      expect(m[t.$1], isA<List>(), reason: t.$1);
    }
    expect((m['namaz_kayitlari'] as List).length, 1);
    expect(m['profil'], isEmpty);
    expect(m[DataExport.consentKey], isA<List>());
    expect(m['eksik_bolumler'], ['cihazlar']);
    expect(m['e_posta'], '');
    expect(m['olusturma_zamani'], '2026-11-11T09:00:00.000Z');
    expect(() => jsonEncode(m), returnsNormally);
  });

  test('Bildirim adresi (FCM anahtarı) ve başkasına ait sütunlar dosyaya alınmaz', () {
    final cols = DataExport.tables.map((t) => t.$3).join(',');
    expect(cols.contains('fcm_token'), isFalse);
    expect(cols.contains('email'), isFalse);
    // Her tablo kullanıcının kendi satırlarıyla sınırlanır
    for (final t in DataExport.tables) {
      expect(['id', 'user_id', 'sender_id'], contains(t.$4), reason: t.$2);
    }
  });

  test('Profil yalnızca okuma izni olan sütunları ister (izinsiz sütun tüm sorguyu düşürür)', () {
    final profil = DataExport.tables.firstWhere((t) => t.$1 == 'profil');
    expect(profil.$3, 'id, display_name, icon, created_at');
  });

  test('Dosya adı tarihli', () {
    expect(DataExport.fileName(DateTime(2026, 1, 5)), 'aile-ile-namaz-verilerim-2026-01-05.json');
  });
}
