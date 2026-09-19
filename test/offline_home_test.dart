import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unitec_entregas/app_state.dart';
import 'package:unitec_entregas/config.dart';
import 'package:unitec_entregas/main.dart';
import 'package:unitec_entregas/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sessão local abre Home sem exigir ERP online', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final config = AppConfig(
      baseUrl: 'http://127.0.0.1:8000',
      lastBaseUrl: 'http://127.0.0.1:8000',
      token: 'token-local',
      userId: 10,
      userName: 'Motorista Offline',
      empresaId: 1,
      empresaNome: 'Empresa Teste',
      deviceUuid: 'device-offline-1',
      deviceApproved: true,
    );

    final state = AppState(config);
    // ready sem ping (simula initialize parcial offline)
    state.ready = true;
    state.connectivity = ErpConnectivity.offline;

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              // Mesmo gate do main.dart
              if (state.hasLocalSession) {
                return const HomeScreen();
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(find.text('Unitec Entregas'), findsWidgets);
    expect(find.textContaining('Motorista Offline'), findsOneWidget);
    expect(find.textContaining('Empresa Teste'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('[Minhas Cargas]'), findsOneWidget);
  });

  test('UnitecEntregasApp aceita estado com sessão', () {
    final config = AppConfig(
      token: 't',
      userId: 1,
      userName: 'A',
      empresaId: 1,
      deviceUuid: 'u',
      deviceApproved: true,
    );
    expect(config.hasLocalSession, isTrue);
    expect(UnitecEntregasApp(state: AppState(config)), isA<UnitecEntregasApp>());
  });
}
