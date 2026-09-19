import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';

import '../app_state.dart';
import '../db/local_db.dart';
import '../motivos_nao_entrega.dart';
import '../widgets/assinatura_pad.dart';

class _ItemEdit {
  _ItemEdit({
    required this.produtoId,
    required this.codigo,
    required this.descricao,
    required this.unidade,
    required this.quantidadeOriginal,
    required this.quantidade,
  });

  final int? produtoId;
  final String codigo;
  final String descricao;
  final String unidade;
  final double quantidadeOriginal;
  double quantidade;
  bool excluido = false;

  Map<String, dynamic> toPayload() => {
        'produto_id': produtoId,
        'codigo': codigo,
        'descricao': descricao,
        'unidade': unidade,
        'quantidade_original': quantidadeOriginal,
        'quantidade': quantidade,
      };
}

class PedidoDetalheScreen extends StatefulWidget {
  const PedidoDetalheScreen({
    super.key,
    required this.cargaId,
    required this.pedidoId,
  });

  final int cargaId;
  final int pedidoId;

  @override
  State<PedidoDetalheScreen> createState() => _PedidoDetalheScreenState();
}

class _PedidoDetalheScreenState extends State<PedidoDetalheScreen> {
  Map<String, dynamic>? _pedido;
  Map<String, dynamic>? _entrega;
  List<_ItemEdit> _itens = [];
  bool _loading = true;
  bool _salvando = false;
  String? _fotoTempPath;
  final _obsCtrl = TextEditingController();
  late final SignatureController _assinaturaCtrl;

  final _money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _qty = NumberFormat('#,##0.###', 'pt_BR');
  final _picker = ImagePicker();

  static const _brand = Color(0xFF1E5A9E);

  @override
  void initState() {
    super.initState();
    _assinaturaCtrl = SignatureController(
      penStrokeWidth: 2.2,
      penColor: Colors.black87,
      exportBackgroundColor: Colors.white,
    );
    _carregar();
  }

  @override
  void dispose() {
    _obsCtrl.dispose();
    _assinaturaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final pedido = await LocalDb.instance.getPedido(widget.cargaId, widget.pedidoId);
    final itens = await LocalDb.instance.listItens(widget.cargaId, widget.pedidoId);
    final entrega = await LocalDb.instance.getEntrega(widget.cargaId, widget.pedidoId);
    if (!mounted) return;
    setState(() {
      _pedido = pedido;
      _itens = itens.map((it) {
        final q = (it['quantidade'] as num?)?.toDouble() ?? 0;
        return _ItemEdit(
          produtoId: it['produto_id'] is int ? it['produto_id'] as int : int.tryParse('${it['produto_id']}'),
          codigo: (it['codigo'] ?? '').toString(),
          descricao: (it['descricao'] ?? 'Produto').toString(),
          unidade: (it['unidade'] ?? 'UN').toString(),
          quantidadeOriginal: q,
          quantidade: q,
        );
      }).toList();
      _entrega = entrega;
      _loading = false;
      if (entrega != null) {
        _obsCtrl.text = (entrega['observacao'] ?? '').toString();
      }
    });
  }

  Future<void> _tirarFoto() async {
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (shot == null || !mounted) return;
      setState(() => _fotoTempPath = shot.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir a câmera: $e')),
      );
    }
  }

  List<_ItemEdit> get _itensAtivos =>
      _itens.where((i) => !i.excluido && i.quantidade > 0).toList();

  bool get _ehParcial {
    final ativos = _itensAtivos;
    if (ativos.length != _itens.length) return true;
    for (final it in ativos) {
      if ((it.quantidade - it.quantidadeOriginal).abs() > 0.0005) return true;
    }
    return false;
  }

  Future<void> _concluir() async {
    if (_entrega != null) return;

    final ativos = _itensAtivos;
    if (ativos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum item restante. Use Não entregue.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      List<int>? assinaturaBytes;
      if (_assinaturaCtrl.isNotEmpty) {
        final png = await _assinaturaCtrl.toPngBytes();
        if (png != null && png.isNotEmpty) {
          assinaturaBytes = png;
        }
      }

      if (!mounted) return;
      final status = _ehParcial ? 'parcial' : 'entregue';
      final state = context.read<AppState>();
      final entrega = await state.concluirEntrega(
        cargaId: widget.cargaId,
        pedidoId: widget.pedidoId,
        fotoTempPath: _fotoTempPath,
        assinaturaBytes: assinaturaBytes,
        observacao: _obsCtrl.text.trim().isEmpty ? null : _obsCtrl.text.trim(),
        itens: ativos.map((e) => e.toPayload()).toList(),
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _entrega = entrega;
        _fotoTempPath = null;
        _salvando = false;
      });
      final sync = (entrega['sync_status'] ?? '').toString();
      final titulo = status == 'parcial' ? 'Entrega parcial' : 'Entregue';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sync == 'sincronizado' ? titulo : '$titulo — aguardando sincronização',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao concluir: $e')),
      );
    }
  }

  Future<void> _abrirNaoEntregue() async {
    if (_entrega != null || _salvando) return;

    String? motivoSel;
    final obsCtrl = TextEditingController();
    String? fotoTemp = _fotoTempPath;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Não entregue'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Motivo (obrigatório):'),
                    const SizedBox(height: 6),
                    ...MotivosNaoEntrega.labels.entries.map((e) {
                      final selected = motivoSel == e.key;
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          selected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: selected ? _brand : Colors.grey,
                          size: 20,
                        ),
                        title: Text(e.value, style: const TextStyle(fontSize: 14)),
                        onTap: () => setLocal(() => motivoSel = e.key),
                      );
                    }),
                    const SizedBox(height: 6),
                    TextField(
                      controller: obsCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: motivoSel == MotivosNaoEntrega.outro
                            ? 'Observação (obrigatória)'
                            : 'Observação (opcional)',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final shot = await _picker.pickImage(
                            source: ImageSource.camera,
                            imageQuality: 85,
                            maxWidth: 1600,
                          );
                          if (shot != null) {
                            setLocal(() => fotoTemp = shot.path);
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Câmera: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.photo_camera, size: 18),
                      label: Text(fotoTemp == null ? 'Foto (opcional)' : 'Foto selecionada'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                FilledButton(
                  onPressed: () {
                    if (motivoSel == null) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Selecione o motivo.')),
                      );
                      return;
                    }
                    if (motivoSel == MotivosNaoEntrega.outro && obsCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Informe a observação para Outro.')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );

    final motivo = motivoSel;
    final obs = obsCtrl.text.trim();
    obsCtrl.dispose();
    if (ok != true || motivo == null || !mounted) return;

    setState(() => _salvando = true);
    try {
      final entrega = await context.read<AppState>().registrarNaoEntrega(
        cargaId: widget.cargaId,
        pedidoId: widget.pedidoId,
        motivo: motivo,
        observacao: obs.isEmpty ? null : obs,
        fotoTempPath: fotoTemp,
      );
      if (!mounted) return;
      setState(() {
        _entrega = entrega;
        _fotoTempPath = null;
        _salvando = false;
      });
      final sync = (entrega['sync_status'] ?? '').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sync == 'sincronizado'
                ? 'Não entregue — sincronizado'
                : 'Não entregue — aguardando sincronização',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha: $e')),
      );
    }
  }

  Future<void> _editarQuantidade(_ItemEdit item) async {
    final ctrl = TextEditingController(text: _qty.format(item.quantidade).replaceAll('.', ''));
    // Use decimal with comma for BR
    ctrl.text = item.quantidade.toString().replaceAll('.', ',');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quantidade'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: item.unidade,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
        ],
      ),
    );
    if (ok != true || !mounted) {
      ctrl.dispose();
      return;
    }
    final raw = ctrl.text.trim().replaceAll('.', '').replaceAll(',', '.');
    ctrl.dispose();
    final v = double.tryParse(raw);
    if (v == null || v < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantidade inválida.')),
      );
      return;
    }
    if (v > item.quantidadeOriginal + 0.0005) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Máximo: ${_qty.format(item.quantidadeOriginal)} ${item.unidade}')),
      );
      return;
    }
    setState(() {
      item.quantidade = v;
      if (v <= 0) item.excluido = true;
    });
  }

  Color _bannerColor(Map<String, dynamic> e) {
    final s = (e['status'] ?? '').toString();
    if (s == 'nao_entregue') return const Color(0xFFFFF3E0);
    if (s == 'parcial') return const Color(0xFFE3F2FD);
    return const Color(0xFFE8F5E9);
  }

  Color _bannerBorder(Map<String, dynamic> e) {
    final s = (e['status'] ?? '').toString();
    if (s == 'nao_entregue') return const Color(0xFFEF6C00);
    if (s == 'parcial') return const Color(0xFF1565C0);
    return const Color(0xFF2E7D32);
  }

  String _statusTitulo(Map<String, dynamic> e) {
    final s = (e['status'] ?? '').toString();
    if (s == 'nao_entregue') return '⚠ Não entregue';
    if (s == 'parcial') return '◐ Entrega parcial';
    return '✓ Entregue';
  }

  String _statusSub(Map<String, dynamic> e) {
    final sync = (e['sync_status'] ?? '').toString();
    final syncLabel = sync == 'sincronizado'
        ? 'sincronizado'
        : (sync == 'erro' ? 'aguardando sincronização (erro)' : 'aguardando sincronização');

    if ((e['status'] ?? '') == 'nao_entregue') {
      final motivo = MotivosNaoEntrega.label(e['motivo_nao_entrega']?.toString());
      return '$motivo — $syncLabel';
    }
    return syncLabel[0].toUpperCase() + syncLabel.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_pedido == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pedido')),
        body: const Center(child: Text('Pedido não encontrado no aparelho.')),
      );
    }

    final p = _pedido!;
    final valor = (p['valor_total'] as num?)?.toDouble() ?? 0;
    final concluida = _entrega != null;
    final fotoPath = concluida
        ? (_entrega!['foto_path']?.toString() ?? '')
        : (_fotoTempPath ?? '');
    final assinaturaPath = concluida ? (_entrega!['assinatura_path']?.toString() ?? '') : '';
    final itensVisiveis = _itens.where((i) => !i.excluido && i.quantidade > 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido ${(p['numero'] ?? p['pedido_id']).toString()}'),
        backgroundColor: _brand,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        children: [
          if (concluida) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _bannerColor(_entrega!),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _bannerBorder(_entrega!)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusTitulo(_entrega!),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _bannerBorder(_entrega!),
                      fontSize: 14,
                    ),
                  ),
                  Text(_statusSub(_entrega!), style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          _infoCard(p, valor),
          const SizedBox(height: 10),
          Row(
            children: [
              _sectionTitle('Itens'),
              const Spacer(),
              if (!concluida && _ehParcial)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Parcial',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1565C0)),
                  ),
                ),
            ],
          ),
          if (!concluida)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                'Toque na qtd para alterar ou exclua o item',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
          const SizedBox(height: 4),
          if (itensVisiveis.isEmpty)
            const Text('Sem itens.', style: TextStyle(fontSize: 13, color: Colors.black54))
          else
            ...itensVisiveis.map((it) => _itemTile(it, concluida)),
          const SizedBox(height: 12),
          _sectionTitle('Comprovante'),
          const SizedBox(height: 4),
          if (fotoPath.isNotEmpty && File(fotoPath).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(fotoPath),
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else if (!concluida)
            Container(
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD0D7E2)),
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFFF8FAFC),
              ),
              child: Text(
                'Nenhuma foto',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
          if (!concluida) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: _salvando ? null : _tirarFoto,
                icon: const Icon(Icons.photo_camera, size: 18),
                label: const Text('TIRAR FOTO'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _brand,
                  side: const BorderSide(color: _brand),
                ),
              ),
            ),
            const SizedBox(height: 10),
            AssinaturaPad(controller: _assinaturaCtrl),
            const SizedBox(height: 10),
            TextField(
              controller: _obsCtrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Observação',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: _salvando ? null : _concluir,
                style: FilledButton.styleFrom(backgroundColor: _brand),
                child: _salvando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_ehParcial ? 'CONCLUIR PARCIAL' : 'CONCLUIR ENTREGA'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              child: OutlinedButton(
                onPressed: _salvando ? null : _abrirNaoEntregue,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF6C00),
                  side: const BorderSide(color: Color(0xFFEF6C00)),
                ),
                child: const Text('NÃO ENTREGUE'),
              ),
            ),
          ] else ...[
            if (assinaturaPath.isNotEmpty && File(assinaturaPath).existsSync()) ...[
              const SizedBox(height: 8),
              _sectionTitle('Assinatura'),
              const SizedBox(height: 4),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD0D7E2)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.file(File(assinaturaPath), fit: BoxFit.contain),
              ),
            ],
            if ((_entrega!['observacao'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _sectionTitle('Observação'),
              Text(_entrega!['observacao'].toString(), style: const TextStyle(fontSize: 13)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _itemTile(_ItemEdit it, bool concluida) {
    final alterado = (it.quantidade - it.quantidadeOriginal).abs() > 0.0005;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: alterado ? const Color(0xFF90CAF9) : const Color(0xFFD0D7E2)),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  it.descricao,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  'Cód. ${it.codigo.isEmpty ? '—' : it.codigo}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                if (alterado)
                  Text(
                    'Original: ${_qty.format(it.quantidadeOriginal)} ${it.unidade}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF1565C0)),
                  ),
              ],
            ),
          ),
          if (!concluida) ...[
            IconButton(
              tooltip: 'Diminuir',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() {
                  final step = it.quantidadeOriginal >= 1 ? 1.0 : 0.1;
                  it.quantidade = (it.quantidade - step).clamp(0, it.quantidadeOriginal);
                  if (it.quantidade <= 0) it.excluido = true;
                });
              },
              icon: const Icon(Icons.remove_circle_outline, size: 20),
            ),
            InkWell(
              onTap: () => _editarQuantidade(it),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  '${_qty.format(it.quantidade)} ${it.unidade}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _brand),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Aumentar',
              visualDensity: VisualDensity.compact,
              onPressed: it.quantidade >= it.quantidadeOriginal
                  ? null
                  : () {
                      setState(() {
                        final step = it.quantidadeOriginal >= 1 ? 1.0 : 0.1;
                        it.quantidade = (it.quantidade + step).clamp(0, it.quantidadeOriginal);
                      });
                    },
              icon: const Icon(Icons.add_circle_outline, size: 20),
            ),
            IconButton(
              tooltip: 'Excluir item',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => it.excluido = true),
              icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFC62828)),
            ),
          ] else
            Text(
              '${_qty.format(it.quantidade)} ${it.unidade}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: Color(0xFF0F3460),
      ),
    );
  }

  Widget _infoCard(Map<String, dynamic> p, double valor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD0D7E2)),
      ),
      child: Column(
        children: [
          _kv('Cliente', (p['cliente'] ?? '—').toString()),
          _kv('Endereço', (p['endereco'] ?? '—').toString()),
          _kv('Telefone', (p['telefone'] ?? '—').toString()),
          _kv('Documento', (p['documento'] ?? '—').toString()),
          _kv('Valor', _money.format(valor), last: true),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
