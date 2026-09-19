import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<dynamic> _empresas = [];
  List<dynamic> _usuarios = [];
  int? _empresaId;
  int? _userId;
  final _senha = TextEditingController();
  bool _loading = true;
  bool _carregandoUsuarios = false;
  bool _entrando = false;
  String? _erro;

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  static String _empresaLabel(dynamic e) {
    final nome = (e['nome'] ?? '').toString().trim();
    if (nome.isNotEmpty) return nome;
    return 'Empresa #${e['id']}';
  }

  @override
  void initState() {
    super.initState();
    _carregarEmpresas();
  }

  @override
  void dispose() {
    _senha.dispose();
    super.dispose();
  }

  Future<void> _carregarEmpresas() async {
    setState(() {
      _loading = true;
      _erro = null;
    });
    final state = context.read<AppState>();
    try {
      await state.refreshApproval();
      if (!mounted) return;
      if (!state.isApproved) {
        setState(() => _loading = false);
        return;
      }
      final info = await state.info();
      final empresas = List<dynamic>.from(info['empresas'] as List<dynamic>? ?? []);
      await state.cacheEmpresas(empresas);
      final lastId = state.config.empresaId;
      setState(() {
        _empresas = empresas;
        _empresaId = lastId != null && empresas.any((e) => _asInt(e['id']) == lastId)
            ? lastId
            : (empresas.isNotEmpty ? _asInt(empresas.first['id']) : null);
        _loading = false;
      });
      if (_empresaId != null) await _carregarUsuarios();
    } catch (e) {
      final voltou = await state.syncDeviceApprovalFromError(e);
      if (!mounted) return;
      if (voltou) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _erro = 'Não foi possível carregar empresas: $e';
        _loading = false;
      });
    }
  }

  Future<void> _carregarUsuarios() async {
    if (_empresaId == null) return;
    setState(() {
      _carregandoUsuarios = true;
      _usuarios = [];
      _userId = null;
    });
    final state = context.read<AppState>();
    try {
      final users = await state.usuariosDaEmpresa(_empresaId!);
      await state.cacheUsuarios(_empresaId!, users);
      if (!mounted) return;
      final lastUser = state.config.userId;
      setState(() {
        _usuarios = users;
        _userId = lastUser != null && users.any((u) => _asInt(u['id']) == lastUser)
            ? lastUser
            : (users.isNotEmpty ? _asInt(users.first['id']) : null);
        _carregandoUsuarios = false;
      });
    } catch (e) {
      final voltou = await state.syncDeviceApprovalFromError(e);
      if (!mounted) return;
      setState(() {
        _erro = voltou ? null : 'Não foi possível carregar usuários: $e';
        _carregandoUsuarios = false;
      });
    }
  }

  Future<void> _entrar() async {
    if (_empresaId == null || _userId == null) {
      setState(() => _erro = 'Selecione empresa e usuário.');
      return;
    }
    if (_senha.text.isEmpty) {
      setState(() => _erro = 'Informe a senha do app.');
      return;
    }
    setState(() {
      _entrando = true;
      _erro = null;
    });
    final state = context.read<AppState>();
    final empresa = _empresas.firstWhere(
      (e) => _asInt(e['id']) == _empresaId,
      orElse: () => {'nome': 'Empresa'},
    );
    try {
      await state.login(
        empresaId: _empresaId!,
        empresaNome: _empresaLabel(empresa),
        userId: _userId!,
        senha: _senha.text,
      );
    } catch (e) {
      final voltou = await state.syncDeviceApprovalFromError(e);
      if (!mounted) return;
      setState(() {
        _erro = voltou ? 'Aparelho aguardando autorização.' : '$e';
        _entrando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      'Entrar',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text('Use a senha do app (mesma do Força de Vendas).'),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<int>(
                      initialValue: _empresaId,
                      decoration: const InputDecoration(
                        labelText: 'Empresa',
                        border: OutlineInputBorder(),
                      ),
                      items: _empresas
                          .map(
                            (e) => DropdownMenuItem(
                              value: _asInt(e['id']),
                              child: Text(_empresaLabel(e)),
                            ),
                          )
                          .where((i) => i.value != null)
                          .toList(),
                      onChanged: (v) async {
                        setState(() => _empresaId = v);
                        await _carregarUsuarios();
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_carregandoUsuarios)
                      const LinearProgressIndicator()
                    else
                      DropdownButtonFormField<int>(
                        initialValue: _userId,
                        decoration: const InputDecoration(
                          labelText: 'Motorista / usuário',
                          border: OutlineInputBorder(),
                        ),
                        items: _usuarios
                            .map(
                              (u) => DropdownMenuItem(
                                value: _asInt(u['id']),
                                child: Text((u['name'] ?? '').toString()),
                              ),
                            )
                            .where((i) => i.value != null)
                            .toList(),
                        onChanged: (v) => setState(() => _userId = v),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _senha,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Senha do app',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _entrar(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _entrando ? null : _entrar,
                      child: _entrando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Entrar'),
                    ),
                    if (_erro != null) ...[
                      const SizedBox(height: 16),
                      Text(_erro!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => context.read<AppState>().disconnect(),
                      child: const Text('Trocar servidor'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
