import 'package:aile_ile_namaz/screens/home_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ücretsiz sürümde Bugün ve (pasif) Aile açılır; Kaza ve Karne kilitli', () {
    expect(HomeShellTabs.locked(0, demo: true), isFalse);
    expect(HomeShellTabs.locked(1, demo: true), isFalse); // katılım ve Pro isteği için açık
    for (final i in [2, 3]) {
      expect(HomeShellTabs.locked(i, demo: true), isTrue, reason: 'sekme $i');
    }
  });

  test('Pro / denemede tüm sekmeler açık', () {
    for (final i in [0, 1, 2, 3]) {
      expect(HomeShellTabs.locked(i, demo: false), isFalse, reason: 'sekme $i');
    }
  });
}
