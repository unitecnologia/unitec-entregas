import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/local_db.dart';
import '../motivos_nao_entrega.dart';
import 'pedido_detalhe_screen.dart';

class CargaDetalheScreen extends StatefulWidget {
  const CargaDetalheScreen({super.key, required this.cargaId});

  final int cargaId;

  @override
  State<CargaDetalheScreen> createState() => _CargaDetalheScreenState();
}

class _CargaDetalheScreenState extends State<CargaDetalheScreen> {
  Map<String, dynamic>? _carga;
  List<Map<String, dynamic>> _pedidos = [];
  Map<int, Map<String, dynamic>> _entregas = {};
  bool _loading = true;

  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static const _brand = Color(0xFF1E5A9E);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final carga = await LocalDb.instance.getCarga(widget.cargaId);
    final pedidos = await LocalDb.instance.listPedidos(widget.cargaId);
    final entregas = await LocalDb.instance.entregasDaCarga(widget.cargaId);
    if (!mounted) return;
    setState(() {
      _carga = carga;
      _pedidos = pedidos;
      _entregas = entregas;
      _loading = false;
    });
  }

  String _numeroCarga(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return raw ?? '—';
    return digits.padLeft(6, '0');
  }

  Widget _statusChip(Map<String, dynamic>? entrega) {
    if (entrega == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF9C3),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text('Pendente', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFA16207))),
      );
    }
    final s = (entrega['status'] ?? '').toString();
    if (s == 'nao_entregue') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text('Não entregue', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEF6C00))),
      );
    }
    if (s == 'parcial') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFE3F2FD),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text('Parcial', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1565C0))),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text('Entregue', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_carga == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Carga')),
        body: const Center(child: Text('Carga não encontrada no aparelho.')),
      );
    }

    final numero = _numeroCarga(_carga!['numero']?.toString());
    final entregues = _entregas.values.where((e) => (e['status'] ?? '') == 'entregue').length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Carga $numero'),
        backgroundColor: _brand,
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              '${_pedidos.length} pedidos · $entregues entregues',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
            ),
          ),
          Expanded(
            child: _pedidos.isEmpty
                ? const Center(child: Text('Nenhum pedido nesta carga.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: _pedidos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final p = _pedidos[i];
                      final pedidoId = p['pedido_id'] as int;
                      final entrega = _entregas[pedidoId];
                      final valor = (p['valor_total'] as num?)?.toDouble() ?? 0;
                      final motivo = entrega != null && (entrega['status'] ?? '') == 'nao_entregue'
                          ? MotivosNaoEntrega.label(entrega['motivo_nao_entrega']?.toString())
                          : null;

                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PedidoDetalheScreen(
                                  cargaId: widget.cargaId,
                                  pedidoId: pedidoId,
                                ),
                              ),
                            );
                            await _carregar();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFD0D7E2)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              (p['cliente'] ?? 'Cliente').toString(),
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          _statusChip(entrega),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Ped. ${(p['numero'] ?? p['pedido_id'])}  ·  ${_money.format(valor)}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                      ),
                                      Text(
                                        (p['endereco'] ?? 'Sem endereço').toString(),
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (motivo != null)
                                        Text(
                                          motivo,
                                          style: const TextStyle(fontSize: 11, color: Color(0xFFEF6C00)),
                                        ),
                                    ],
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(left: 4, top: 2),
                                  child: Icon(Icons.chevron_right, size: 20, color: Color(0xFF64748B)),
                                ),
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
