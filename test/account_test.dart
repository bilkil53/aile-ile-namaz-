import 'package:aile_ile_namaz/local_store.dart';
import 'package:aile_ile_namaz/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aynı telefonda hesap değişince bir hesabın verisi diğerine geçmemeli.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> start(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    await AppSettings.init();
  }

  const userData = <String, Object>{
    'queue': '[{"t":"prayer","date":"2026-11-08","key":"fajr","status":"PRAYED"}]',
    'lp_2026-11-08': '{"fajr":"PRAYED"}',
    'lk': '{"FAJR":[3,1]}',
    'myName': 'Ali',
    'familySnapshot': '{}',
    'cuma.myGender': 'm',
  };
  const deviceData = <String, Object>{'cityName': 'Ankara', 'pt_2026-11-08': '{}', 'familyAlerts': true};

  test('Hangi anahtarların hesaba ait olduğu', () {
    for (final k in userData.keys) {
      expect(LocalStore.isUserKey(k), isTrue, reason: k);
    }
    for (final k in deviceData.keys) {
      expect(LocalStore.isUserKey(k), isFalse, reason: k);
    }
  });

  test('Başka hesap girince önceki hesabın kuyruğu ve verisi silinir, cihaz ayarları kalır', () async {
    await start({...userData, ...deviceData, 'store.owner': 'A'});
    expect(LocalStore.bindUser('B'), isTrue);
    expect(LocalStore.queue(), isEmpty);
    expect(LocalStore.pendingCount, 0);
    for (final k in userData.keys) {
      expect(AppSettings.prefs.containsKey(k), isFalse, reason: k);
    }
    for (final k in deviceData.keys) {
      expect(AppSettings.prefs.containsKey(k), isTrue, reason: k);
    }
    expect(AppSettings.prefs.getString('store.owner'), 'B');
  });

  test('Aynı hesap tekrar girince hiçbir şey silinmez', () async {
    await start({...userData, 'store.owner': 'A'});
    expect(LocalStore.bindUser('A'), isFalse);
    expect(LocalStore.pendingCount, 1);
    expect(AppSettings.prefs.getString('lk'), isNotNull);
  });

  test('Eski sürümden gelen sahipsiz veri ilk hesabındır (güncellemede bekleyen kayıt kaybolmaz)', () async {
    await start({...userData});
    expect(LocalStore.bindUser('A'), isFalse);
    expect(LocalStore.pendingCount, 1);
    expect(AppSettings.prefs.getString('store.owner'), 'A');
  });

  test('Çıkışta hesabın telefondaki verisi silinir', () async {
    await start({...userData, ...deviceData, 'store.owner': 'A'});
    LocalStore.wipeUserData();
    expect(LocalStore.pendingCount, 0);
    expect(AppSettings.prefs.containsKey('store.owner'), isFalse);
    expect(AppSettings.prefs.getString('cityName'), 'Ankara');
  });

  test('Vaktin bekliyor / bulutta işareti kuyruğa göre değişir ve ekrana haber verilir', () async {
    await start({'store.owner': 'A'});
    var changes = 0;
    void listener() => changes++;
    LocalStore.queueChanged.addListener(listener);
    addTearDown(() => LocalStore.queueChanged.removeListener(listener));
    expect(LocalStore.isPrayerPending('2026-11-09', 'fajr'), isFalse);
    final op = <String, dynamic>{'t': 'prayer', 'date': '2026-11-09', 'key': 'fajr', 'status': 'PRAYED'};
    await LocalStore.enqueue(op);
    expect(LocalStore.isPrayerPending('2026-11-09', 'fajr'), isTrue);
    expect(LocalStore.isPrayerPending('2026-11-09', 'isha'), isFalse);
    await LocalStore.removeOp(op);
    expect(LocalStore.isPrayerPending('2026-11-09', 'fajr'), isFalse);
    expect(changes, greaterThanOrEqualTo(2));
  });
}
