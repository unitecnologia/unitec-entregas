import 'dart:async';
import 'dart:convert';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'api/api_client.dart';
import 'config.dart';
import 'config/erp_url.dart';
import 'db/local_db.dart';

enum ErpConnectivity { online, offline, verificando }

class AppState extends ChangeNotifier {
  AppState(this.config) : api = ApiClient(config);

  final AppConfig config;
  final ApiClient api;

  ErpConnectivity connectivity = ErpConnectivity.verificando;
  bool ready = false;
  bool syncing = false;
  String? lastSyncError;

  bool get isConnected => config.isConnected;
  bool get isApproved => config.isApproved;
  bool get isLoggedIn => config.isLoggedIn;
  bool get hasLocalSession => config.hasLocalSession;
  bool get isOnline => connectivity == ErpConnectivity.online;

  Future<void> initialize() async {
    await ensureDeviceIdentity();
    await LocalDb.instance.database;

    if (config.baseUrl.isEmpty && config.lastBaseUrl.isNotEmpty) {
      config.baseUrl = config.lastBaseUrl;
      await config.save();
    }

    ready = true;
    notifyListeners();

    // Sessão local: Home imediata; ping + sync em background.
    if (hasLocalSession) {
      unawaited(refreshConnectivity(syncIfOnline: true));
    } else if (config.baseUrl.isNotEmpty) {
      unawaited(refreshConnectivity());
    } else {
      connectivity = ErpConnectivity.offline;
      notifyListeners();
    }
  }

  Future<void> refreshConnectivity({bool syncIfOnline = false}) async {
    final base = config.baseUrl.isNotEmpty ? config.baseUrl : config.lastBaseUrl;
    if (base.isEmpty) {
      connectivity = ErpConnectivity.offline;
      notifyListeners();
      return;
    }

    connectivity = ErpConnectivity.verificando;
    notifyListeners();

    final r = await ApiClient.pingDetailed(base, timeout: const Duration(seconds: 4));
    connectivity = r.ok ? ErpConnectivity.online : ErpConnectivity.offline;
    notifyListeners();

    if (syncIfOnline && connectivity == ErpConnectivity.online && hasLocalSession) {
      unawaited(syncAll());
    }
  }

  /// Pull + push pendentes. Falha não desloga nem apaga dados.
  Future<bool> syncAll() async {
    final pullOk = await syncCargas();
    await syncPushPendentes();
    return pullOk;
  }

  /// Baixa cargas do ERP e grava no SQLite. Falha não desloga nem apaga dados.
  Future<bool> syncCargas() async {
    if (!hasLocalSession) return false;
    if (syncing) return false;

    syncing = true;
    lastSyncError = null;
    notifyListeners();

    try {
      if (connectivity != ErpConnectivity.online) {
        final r = await ApiClient.pingDetailed(
          config.baseUrl.isNotEmpty ? config.baseUrl : config.lastBaseUrl,
          timeout: const Duration(seconds: 4),
        );
        connectivity = r.ok ? ErpConnectivity.online : ErpConnectivity.offline;
        if (!r.ok) {
          lastSyncError = 'Offline — usando dados salvos no aparelho';
          return false;
        }
      }

      final data = await api.syncPull();
      final cargas = (data['cargas'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      await LocalDb.instance.upsertCargasFromPull(cargas);
      lastSyncError = null;
      return true;
    } catch (e) {
      lastSyncError = e.toString();
      return false;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// Envia entregas pendentes da sync_queue (uma por vez).
  Future<void> syncPushPendentes() async {
    if (!hasLocalSession) return;

    if (connectivity != ErpConnectivity.online) {
      final r = await ApiClient.pingDetailed(
        config.baseUrl.isNotEmpty ? config.baseUrl : config.lastBaseUrl,
        timeout: const Duration(seconds: 4),
      );
      connectivity = r.ok ? ErpConnectivity.online : ErpConnectivity.offline;
      notifyListeners();
      if (!r.ok) return;
    }

    final items = await LocalDb.instance.pendingQueueItems();
    for (final item in items) {
      final queueId = item['id'] as int;
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(item['payload'] as String) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      final uuid = (payload['app_local_uuid'] ?? item['entity_id'] ?? '').toString();
      final cargaId = payload['carga_id'] is int
          ? payload['carga_id'] as int
          : int.tryParse('${payload['carga_id']}');
      final pedidoId = payload['pedido_id'] is int
          ? payload['pedido_id'] as int
          : int.tryParse('${payload['pedido_id']}');
      final status = (payload['status'] ?? 'entregue').toString();
      final fotoPath = (payload['foto_path'] ?? '').toString();
      final assinaturaPath = (payload['assinatura_path'] ?? '').toString();
      final itensRaw = payload['itens'];
      final itens = <Map<String, dynamic>>[];
      if (itensRaw is List) {
        for (final row in itensRaw) {
          if (row is Map) {
            itens.add(Map<String, dynamic>.from(row));
          }
        }
      }

      if (uuid.isEmpty || cargaId == null || pedidoId == null) {
        await LocalDb.instance.markEntregaErro(
          appLocalUuid: uuid.isEmpty ? 'unknown' : uuid,
          queueId: queueId,
          error: 'Payload inválido',
        );
        continue;
      }

      await LocalDb.instance.markQueueSyncing(queueId);
      notifyListeners();

      try {
        await api.syncPushEntrega(
          appLocalUuid: uuid,
          cargaId: cargaId,
          pedidoId: pedidoId,
          status: status,
          fotoPath: fotoPath.isEmpty ? null : fotoPath,
          assinaturaPath: assinaturaPath.isEmpty ? null : assinaturaPath,
          motivoNaoEntrega: payload['motivo_nao_entrega']?.toString(),
          observacao: payload['observacao']?.toString(),
          concluidaEm: payload['concluida_em']?.toString(),
          itens: itens.isEmpty ? null : itens,
        );
        await LocalDb.instance.markEntregaSincronizada(
          appLocalUuid: uuid,
          queueId: queueId,
        );
      } catch (e) {
        await LocalDb.instance.markEntregaErro(
          appLocalUuid: uuid,
          queueId: queueId,
          error: e.toString(),
        );
      }
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> concluirEntrega({
    required int cargaId,
    required int pedidoId,
    String? fotoTempPath,
    List<int>? assinaturaBytes,
    String? observacao,
    required List<Map<String, dynamic>> itens,
    required String status,
  }) async {
    String? fotoPermanente;
    if (fotoTempPath != null && fotoTempPath.isNotEmpty) {
      fotoPermanente = await LocalDb.instance.persistFoto(
        tempPath: fotoTempPath,
        cargaId: cargaId,
        pedidoId: pedidoId,
      );
    }

    String? assinaturaPermanente;
    if (assinaturaBytes != null && assinaturaBytes.isNotEmpty) {
      assinaturaPermanente = await LocalDb.instance.persistAssinaturaBytes(
        bytes: assinaturaBytes,
        cargaId: cargaId,
        pedidoId: pedidoId,
      );
    }

    final entrega = await LocalDb.instance.concluirEntregaLocal(
      cargaId: cargaId,
      pedidoId: pedidoId,
      status: status,
      fotoPath: fotoPermanente,
      assinaturaPath: assinaturaPermanente,
      observacao: observacao,
      itens: itens,
    );
    notifyListeners();
    if (connectivity == ErpConnectivity.online) {
      unawaited(syncPushPendentes());
    }
    return entrega;
  }

  Future<Map<String, dynamic>> registrarNaoEntrega({
    required int cargaId,
    required int pedidoId,
    required String motivo,
    String? observacao,
    String? fotoTempPath,
  }) async {
    String? permanente;
    if (fotoTempPath != null && fotoTempPath.isNotEmpty) {
      permanente = await LocalDb.instance.persistFoto(
        tempPath: fotoTempPath,
        cargaId: cargaId,
        pedidoId: pedidoId,
      );
    }
    final entrega = await LocalDb.instance.concluirEntregaLocal(
      cargaId: cargaId,
      pedidoId: pedidoId,
      status: 'nao_entregue',
      fotoPath: permanente,
      motivoNaoEntrega: motivo,
      observacao: observacao,
    );
    notifyListeners();
    if (connectivity == ErpConnectivity.online) {
      unawaited(syncPushPendentes());
    }
    return entrega;
  }

  Future<void> ensureDeviceIdentity() async {
    var changed = false;
    if (config.deviceUuid.isEmpty) {
      config.deviceUuid = const Uuid().v4();
      changed = true;
    }
    if (config.deviceName.isEmpty) {
      config.deviceName = await _defaultDeviceName();
      changed = true;
    }
    if (changed) {
      await config.save();
      notifyListeners();
    }
  }

  Future<String> _defaultDeviceName() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final brand = info.brand.isNotEmpty
          ? '${info.brand[0].toUpperCase()}${info.brand.substring(1)}'
          : '';
      final name = '$brand ${info.model}'.trim();
      return name.isEmpty ? 'Aparelho Android' : name;
    } catch (_) {
      return 'Aparelho Android';
    }
  }

  Future<void> connectManual(String url) async {
    final clean = ErpUrl.normalize(url);
    if (clean.isEmpty) {
      throw Exception('Informe o endereço do servidor.');
    }
    final r = await ApiClient.pingDetailed(clean, timeout: const Duration(seconds: 5));
    if (!r.ok) {
      throw Exception('Não foi possível conectar em $clean: ${r.message}');
    }
    await _applyConnection(clean);
    connectivity = ErpConnectivity.online;
    notifyListeners();
  }

  Future<void> connectFound(String baseUrl) async {
    await _applyConnection(baseUrl);
    connectivity = ErpConnectivity.online;
    notifyListeners();
  }

  Future<void> _applyConnection(String baseUrl) async {
    config.baseUrl = baseUrl;
    config.lastBaseUrl = baseUrl;
    await ensureDeviceIdentity();
    await config.save();
    notifyListeners();
  }

  Future<String> registerDevice() async {
    await ensureDeviceIdentity();
    final resp = await api.registerDevice(deviceName: config.deviceName);
    config.pairingCode = (resp['pairing_code'] ?? '').toString();
    config.deviceApproved = resp['approved'] == true;
    await config.save();
    notifyListeners();
    return config.pairingCode;
  }

  Future<void> refreshApproval() async {
    final resp = await api.deviceStatus();
    config.deviceApproved = resp['approved'] == true;
    if (resp['pairing_code'] != null) {
      config.pairingCode = resp['pairing_code'].toString();
    }
    await config.save();
    notifyListeners();
  }

  Future<bool> syncDeviceApprovalFromError(Object e) async {
    if (e is ApiException && e.isDeviceBlocked) {
      config.deviceApproved = false;
      await config.save();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> info() => api.info();

  Future<List<dynamic>> usuariosDaEmpresa(int empresaId) => api.usuarios(empresaId);

  Future<void> cacheEmpresas(List<dynamic> empresas) async {
    config.cachedEmpresasJson = jsonEncode(empresas);
    await config.save();
  }

  Future<void> cacheUsuarios(int empresaId, List<dynamic> users) async {
    Map<String, dynamic> map = {};
    try {
      map = jsonDecode(config.cachedUsuariosJson) as Map<String, dynamic>? ?? {};
    } catch (_) {}
    map['$empresaId'] = users;
    config.cachedUsuariosJson = jsonEncode(map);
    await config.save();
  }

  List<dynamic> empresasEmCache() {
    try {
      final list = jsonDecode(config.cachedEmpresasJson);
      return list is List ? list : [];
    } catch (_) {
      return [];
    }
  }

  List<dynamic> usuariosEmCache(int empresaId) {
    try {
      final map = jsonDecode(config.cachedUsuariosJson) as Map<String, dynamic>? ?? {};
      final list = map['$empresaId'];
      return list is List ? list : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> login({
    required int empresaId,
    required String empresaNome,
    required int userId,
    required String senha,
  }) async {
    final resp = await api.login(
      empresaId: empresaId,
      userId: userId,
      senha: senha,
      deviceUuid: config.deviceUuid,
      deviceName: config.deviceName,
    );

    final token = (resp['token'] ?? '').toString();
    if (token.isEmpty) {
      throw Exception('Login sem token.');
    }

    final user = resp['user'] as Map<String, dynamic>? ?? {};
    config.token = token;
    config.empresaId = empresaId;
    config.empresaNome = empresaNome;
    config.userId = user['id'] is int ? user['id'] as int : userId;
    config.userName = (user['name'] ?? user['motorista'] ?? '').toString();
    if (config.userName.isEmpty) {
      config.userName = 'Usuário #$userId';
    }
    config.deviceApproved = true;
    await config.save();
    connectivity = ErpConnectivity.online;
    notifyListeners();
    unawaited(syncAll());
  }

  Future<void> logout() async {
    await api.logout();
    config.clearSession();
    await config.save();
    notifyListeners();
  }

  /// Desconecta URL (mantém lastBaseUrl e device). Só se não houver sessão ativa.
  Future<void> disconnect() async {
    config.baseUrl = '';
    await config.save();
    connectivity = ErpConnectivity.offline;
    notifyListeners();
  }
}
