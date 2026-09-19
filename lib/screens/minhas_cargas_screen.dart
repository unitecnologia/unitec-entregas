import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import 'carga_detalhe_screen.dart';

class MinhasCargasScreen extends StatefulWidget {
  const MinhasCargasScreen({super.key});

  @override
  State<MinhasCargasScreen> createState() => _MinhasCargasScreenState();
}

class _MinhasCargasScreenState extends State<MinhasCargasScreen> {
  List<Map<String, dynamic>> _cargas = [];
  bool _loading = true;

  static const _brand = Color(0xFF1E5A9E);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final rows = await LocalDb.instance.listCargas();
    if (!mounted) return;
    setState(() {
      _cargas = rows;
      _loading = false;
    });
  }

  Future<void> _atualizar() async {
    final state = context.read<AppState>();
    await state.syncAll();
    await _carregar();
    if (!mounted) return;
    final msg = state.lastSyncError == null
        ? 'Cargas atualizadas.'
        : 'Não foi possível atualizar: ${state.lastSyncError}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _fmtData(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return DateFormat('dd/MM/yyyy').format(d);
  }

  String _numeroCarga(String? raw) {
    final n = (raw ?? '').trim();
    if (n.isEmpty) return '—';
    final digits = n.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return n;
    return digits.padLeft(6, '0');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final online = state.isOnline;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Minhas Cargas'),
        backgroundColor: _brand,
        foregroundColor: Colors.white,
        actions: [
          if (online)
            IconButton(
              tooltip: 'Atualizar',
              onPressed: state.syncing ? null : _atualizar,
              icon: state.syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_download_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: online ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    online ? Icons.cloud_done : Icons.cloud_off,
                    size: 18,
                    color: online ? const Color(0xFF2E7D32) : const Color(0xFFF57F17),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      online ? 'Online' : 'Offline — dados no aparelho',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: online ? const Color(0xFF2E7D32) : const Color(0xFF6D4C00),
                      ),
                    ),
                  ),
                  if (online)
                    TextButton(
                      onPressed: state.syncing ? null : _atualizar,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: _brand,
                      ),
                      child: const Text('ATUALIZAR'),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _cargas.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Nenhuma carga no aparelho.\nConecte-se e toque em ATUALIZAR.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        itemCount: _cargas.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final c = _cargas[i];
                          final qtd = c['qtd_pedidos'] as int? ?? 0;
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CargaDetalheScreen(cargaId: c['id'] as int),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFD0D7E2)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Carga ${_numeroCarga(c['numero']?.toString())}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              color: Color(0xFF0F3460),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${_fmtData(c['data']?.toString())}  ·  ${(c['veiculo'] ?? '—')}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '$qtd entregas',
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
