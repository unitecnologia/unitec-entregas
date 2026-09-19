import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Sessão + conexão + device, persistidos localmente (offline-first).
class AppConfig {
  AppConfig({
    this.baseUrl = '',
    this.lastBaseUrl = '',
    this.deviceUuid = '',
    this.deviceName = '',
    this.pairingCode = '',
    this.deviceApproved = false,
    this.empresaId,
    this.empresaNome = '',
    this.token = '',
    this.userId,
    this.userName = '',
    this.cachedEmpresasJson = '[]',
    this.cachedUsuariosJson = '{}',
  });

  String baseUrl;
  String lastBaseUrl;
  String deviceUuid;
  String deviceName;
  String pairingCode;
  bool deviceApproved;
  int? empresaId;
  String empresaNome;
  String token;
  int? userId;
  String userName;
  String cachedEmpresasJson;
  String cachedUsuariosJson;

  bool get isConnected => baseUrl.isNotEmpty;
  bool get isApproved => deviceApproved;
  bool get isLoggedIn => token.isNotEmpty;

  /// Sessão local completa: abre Home mesmo sem ERP.
  bool get hasLocalSession =>
      token.isNotEmpty &&
      (userId ?? 0) > 0 &&
      userName.trim().isNotEmpty &&
      (empresaId ?? 0) > 0 &&
      deviceUuid.isNotEmpty &&
      deviceApproved;

  String get apiBase => '$baseUrl/api/v1/entregas';

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'lastBaseUrl': lastBaseUrl,
        'deviceUuid': deviceUuid,
        'deviceName': deviceName,
        'pairingCode': pairingCode,
        'deviceApproved': deviceApproved,
        'empresaId': empresaId,
        'empresaNome': empresaNome,
        'token': token,
        'userId': userId,
        'userName': userName,
        'cachedEmpresasJson': cachedEmpresasJson,
        'cachedUsuariosJson': cachedUsuariosJson,
      };

  static AppConfig fromJson(Map<String, dynamic> j) => AppConfig(
        baseUrl: (j['baseUrl'] ?? '').toString(),
        lastBaseUrl: (j['lastBaseUrl'] ?? '').toString(),
        deviceUuid: (j['deviceUuid'] ?? '').toString(),
        deviceName: (j['deviceName'] ?? '').toString(),
        pairingCode: (j['pairingCode'] ?? '').toString(),
        deviceApproved: j['deviceApproved'] == true,
        empresaId: j['empresaId'] is int
            ? j['empresaId'] as int
            : int.tryParse('${j['empresaId'] ?? ''}'),
        empresaNome: (j['empresaNome'] ?? '').toString(),
        token: (j['token'] ?? '').toString(),
        userId: j['userId'] is int
            ? j['userId'] as int
            : int.tryParse('${j['userId'] ?? ''}'),
        userName: (j['userName'] ?? '').toString(),
        cachedEmpresasJson: (j['cachedEmpresasJson'] ?? '[]').toString(),
        cachedUsuariosJson: (j['cachedUsuariosJson'] ?? '{}').toString(),
      );

  static const _key = 'unitec_entregas_config';

  static Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return AppConfig();
    }
    try {
      return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppConfig();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
  }

  void clearSession() {
    token = '';
    empresaId = null;
    empresaNome = '';
    userId = null;
    userName = '';
  }
}
