import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../app_state.dart';
import 'minhas_cargas_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _statusLabel(ErpConnectivity c) {
    return switch (c) {
      ErpConnectivity.online => 'Online',
      ErpConnectivity.offline => 'Offline',
      ErpConnectivity.verificando => 'Verificando',
    };
  }

  Color _statusColor(ErpConnectivity c) {
    return switch (c) {
      ErpConnectivity.online => const Color(0xFF2E7D32),
      ErpConnectivity.offline => const Color(0xFFC62828),
      ErpConnectivity.verificando => const Color(0xFFF9A825),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final config = state.config;

    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName),
        actions: [
          IconButton(
            tooltip: 'Atualizar status',
            onPressed: () => state.refreshConnectivity(syncIfOnline: true),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sair'),
                  content: const Text('Encerrar sessão neste aparelho?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sair')),
                  ],
                ),
              );
              if (ok == true) await state.logout();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              kAppName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            _InfoRow(label: 'Motorista', value: config.userName.isEmpty ? '—' : config.userName),
            _InfoRow(label: 'Empresa', value: config.empresaNome.isEmpty ? '—' : config.empresaNome),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Status: ', style: Theme.of(context).textTheme.titleMedium),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(state.connectivity).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _statusColor(state.connectivity)),
                  ),
                  child: Text(
                    _statusLabel(state.connectivity),
                    style: TextStyle(
                      color: _statusColor(state.connectivity),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (state.syncing) ...[
                  const SizedBox(width: 10),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MinhasCargasScreen()),
                );
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                side: const BorderSide(color: Color(0xFF0D47A1), width: 1.5),
              ),
              child: const Text(
                '[Minhas Cargas]',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(
        TextSpan(
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black87),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
