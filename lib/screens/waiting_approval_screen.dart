import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class WaitingApprovalScreen extends StatefulWidget {
  const WaitingApprovalScreen({super.key});

  @override
  State<WaitingApprovalScreen> createState() => _WaitingApprovalScreenState();
}

class _WaitingApprovalScreenState extends State<WaitingApprovalScreen> {
  Timer? _timer;
  String? _erro;
  bool _registrando = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final state = context.read<AppState>();
    try {
      await state.registerDevice();
      if (!mounted) return;
      setState(() => _registrando = false);
      if (state.isApproved) return;
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
    } catch (e) {
      if (mounted) {
        setState(() {
          _registrando = false;
          _erro = '$e';
        });
      }
    }
  }

  Future<void> _poll() async {
    final state = context.read<AppState>();
    try {
      await state.refreshApproval();
      if (state.isApproved) {
        _timer?.cancel();
      }
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final code = state.config.pairingCode;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(Icons.phonelink_lock, size: 64, color: Color(0xFF0D47A1)),
              const SizedBox(height: 16),
              Text(
                'Aguardando autorização',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'Peça ao administrador para autorizar este aparelho em Terminais → Aparelhos (Unitec Entregas).',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (_registrando)
                const Center(child: CircularProgressIndicator())
              else ...[
                Text(
                  'Código',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  code.isEmpty ? '—' : code,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        letterSpacing: 6,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0D47A1),
                      ),
                ),
              ],
              if (_erro != null) ...[
                const SizedBox(height: 16),
                Text(_erro!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ],
              const Spacer(),
              OutlinedButton(
                onPressed: () async {
                  await state.disconnect();
                },
                child: const Text('Trocar servidor'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
