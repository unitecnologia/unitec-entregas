import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_info.dart';
import 'app_state.dart';
import 'config.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/waiting_approval_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  final state = AppState(config);
  await state.initialize();
  runApp(UnitecEntregasApp(state: state));
}

class UnitecEntregasApp extends StatelessWidget {
  const UnitecEntregasApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: const _Root(),
      ),
    );
  }
}

/// Gate offline-first:
/// - sessão local completa → Home (ping em background)
/// - sem sessão → conectar → device → login → Home
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (state.hasLocalSession) {
      return const HomeScreen();
    }

    if (!state.isConnected) {
      return const ConnectScreen();
    }

    if (!state.isApproved) {
      return const WaitingApprovalScreen();
    }

    if (!state.isLoggedIn) {
      return const LoginScreen();
    }

    return const HomeScreen();
  }
}
