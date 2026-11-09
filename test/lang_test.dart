import 'package:aile_ile_namaz/lang.dart';
import 'package:aile_ile_namaz/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init();
  });

  test('Seçilen dil metni belirler', () async {
    await Lang.set(AppLang.tr);
    expect(Lang.code, 'tr');
    expect(t('Bugün', 'Today'), 'Bugün');

    await Lang.set(AppLang.en);
    expect(Lang.code, 'en');
    expect(t('Bugün', 'Today'), 'Today');
  });

  test('Telefonun diline göre: seçim silinir, telefon dili kullanılır', () async {
    await Lang.set(AppLang.en);
    await Lang.set(AppLang.system);
    expect(Lang.choice, AppLang.system);
    expect(AppSettings.prefs.getString('lang'), isNull);
    expect(Lang.code, Lang.systemCode);
  });

  test('Dil değişince ekranlara haber verilir', () async {
    var n = 0;
    void inc() => n++;
    Lang.changed.addListener(inc);
    await Lang.set(AppLang.en);
    await Lang.set(AppLang.tr);
    Lang.changed.removeListener(inc);
    expect(n, 2);
  });

  test('Bilinmeyen kayıt telefon diline düşer', () async {
    await AppSettings.prefs.setString('lang', 'de');
    expect(Lang.choice, AppLang.system);
  });
}
