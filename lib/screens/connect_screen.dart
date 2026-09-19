import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../app_state.dart';
import '../net/discovery.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _ipCtrl = TextEditingController();
  bool _buscando = false;
  bool _conectando = false;
  String? _erro;
  String? _progresso;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    state.ensureDeviceIdentity();
    final last = state.config.lastBaseUrl;
    if (last.isNotEmpty) {
      _ipCtrl.text = last.replaceFirst(RegExp(r'^https?://'), '');
    }
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarNaRede() async {
    setState(() {
      _buscando = true;
      _erro = null;
      _progresso = 'Procurando na rede...';
    });
    try {
      final found = await ServerDiscovery.find(
        onProgress: (done, total) {
          if (mounted) setState(() => _progresso = 'Procurando... ($done/$total)');
        },
      );
      if (!mounted) return;
      if (found == null) {
        setState(() {
          _erro = 'Servidor não encontrado. Digite o IP manualmente.';
          _buscando = false;
          _progresso = null;
        });
        return;
      }
      await context.read<AppState>().connectFound(found);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = 'Falha na busca: $e';
          _buscando = false;
          _progresso = null;
        });
      }
    }
  }

  Future<void> _conectarManual([String? endereco]) async {
    final url = (endereco ?? _ipCtrl.text).trim();
    if (url.isEmpty) {
      setState(() => _erro = 'Informe o IP do servidor (ex.: 192.168.0.10).');
      return;
    }
    setState(() {
      _conectando = true;
      _erro = null;
    });
    try {
      await context.read<AppState>().connectManual(url);
    } catch (e) {
      if (mounted) {
        setState(() {
          _erro = '$e';
          _conectando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ocupado = _buscando || _conectando;
    final ultimo = context.read<AppState>().config.lastBaseUrl;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.local_shipping_outlined, size: 64, color: Color(0xFF0D47A1)),
              const SizedBox(height: 12),
              Text(
                kAppName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Conecte ao ERP da loja para o primeiro acesso.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 28),
              if (ultimo.isNotEmpty) ...[
                FilledButton.icon(
                  onPressed: ocupado ? null : () => _conectarManual(ultimo),
                  icon: const Icon(Icons.replay),
                  label: Text('Reconectar (${ultimo.replaceFirst(RegExp(r'^https?://'), '')})'),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.tonalIcon(
                onPressed: ocupado ? null : _buscarNaRede,
                icon: _buscando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find),
                label: Text(_buscando ? (_progresso ?? 'Buscando...') : 'Buscar na rede'),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _ipCtrl,
                enabled: !ocupado,
                decoration: const InputDecoration(
                  labelText: 'IP ou endereço do ERP',
                  hintText: '192.168.0.10 ou 192.168.0.10:8000',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _conectarManual(),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: ocupado ? null : () => _conectarManual(),
                child: _conectando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Conectar'),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 16),
                Text(_erro!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
