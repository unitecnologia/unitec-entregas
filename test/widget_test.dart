import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_entregas/config.dart';

void main() {
  group('AppConfig.hasLocalSession', () {
    test('true quando sessão completa', () {
      final c = AppConfig(
        token: 'abc',
        userId: 1,
        userName: 'João',
        empresaId: 2,
        empresaNome: 'Loja',
        deviceUuid: 'uuid-1',
        deviceApproved: true,
      );
      expect(c.hasLocalSession, isTrue);
    });

    test('false sem token', () {
      final c = AppConfig(
        token: '',
        userId: 1,
        userName: 'João',
        empresaId: 2,
        deviceUuid: 'uuid-1',
        deviceApproved: true,
      );
      expect(c.hasLocalSession, isFalse);
    });

    test('false sem device aprovado', () {
      final c = AppConfig(
        token: 'abc',
        userId: 1,
        userName: 'João',
        empresaId: 2,
        deviceUuid: 'uuid-1',
        deviceApproved: false,
      );
      expect(c.hasLocalSession, isFalse);
    });
  });
}
