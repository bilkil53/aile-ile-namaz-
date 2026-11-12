import 'package:aile_ile_namaz/kvkk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ConsentAction d(bool sb, bool sr, bool lg, bool ls) =>
      Kvkk.decide(serverBeyan: sb, serverRiza: sr, localGiven: lg, localSynced: ls);

  test('Sunucuda iki kayıt da varsa telefonda tanınır (yeni telefonda sorulmaz)', () {
    expect(d(true, true, false, false), ConsentAction.adopt);
    expect(d(true, true, true, true), ConsentAction.adopt);
  });
  test('Telefonda verilmiş ama yazılamamışsa yeniden gönderilir', () {
    expect(d(false, false, true, false), ConsentAction.resend);
    expect(d(true, false, true, false), ConsentAction.resend);
  });
  test('Sunucuda geçerli rıza yoksa her seferinde sorulur', () {
    expect(d(true, false, true, true), ConsentAction.ask); // metin sürümü eskimiş / kayıt silinmiş
    expect(d(false, false, false, false), ConsentAction.ask);
    expect(d(true, false, false, false), ConsentAction.ask);
    expect(d(false, true, true, true), ConsentAction.ask); // "okudum" beyanı eksik
  });
}
