import 'package:aile_ile_namaz/screens/home_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Ücretsiz sürümde yalnızca Bugün sekmesi açık', () {
    expect(HomeShellTabs.locked(0, demo: true), isFalse);
    for (final i in [1, 2, 3]) {
      expect(HomeShellTabs.locked(i, demo: true), isTrue, reason: 'sekme $i');
    }
  });

  test('Pro / denemede tüm sekmeler açık', () {
    for (final i in [0, 1, 2, 3]) {
      expect(HomeShellTabs.locked(i, demo: false), isFalse, reason: 'sekme $i');
    }
  });
}
