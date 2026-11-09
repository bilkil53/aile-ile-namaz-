import 'package:aile_ile_namaz/local_store.dart';
import 'package:aile_ile_namaz/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ayarlar'daki "Verilerin" kutusunun dayandığı bilgiler.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init();
  });

  test('Bekleyenler türe göre sayılır', () async {
    await LocalStore.enqueue({'t': 'prayer', 'date': '2026-11-09', 'key': 'fajr', 'status': 'PRAYED'});
    await LocalStore.enqueue({'t': 'prayer', 'date': '2026-11-09', 'key': 'dhuhr', 'status': 'PRAYED'});
    await LocalStore.enqueue({'t': 'kaza', 'type': 'FAJR', 'o': 3, 'c': 1});
    expect(LocalStore.pendingOf('prayer'), 2);
    expect(LocalStore.pendingOf('kaza'), 1);
    expect(LocalStore.pendingCount, 3);
  });

  test('Son gönderim zamanı kaydedilir ve hesaba aittir', () async {
    expect(LocalStore.lastSynced('prayer'), isNull);
    await LocalStore.markSynced('prayer');
    expect(LocalStore.lastSynced('prayer'), isNotNull);
    expect(LocalStore.isUserKey('sync.prayer'), isTrue); // başka hesap girince silinir
  });
}
