import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_info.dart';
import '../config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get isDeviceBlocked =>
      code == 'device_not_approved' ||
      code == 'device_revoked' ||
      code == 'device_required' ||
      message.toLowerCase().contains('aguardando autorização') ||
      message.toLowerCase().contains('não identificado');

  @override
  String toString() => message;
}

class PingResult {
  PingResult({required this.ok, required this.message, this.ms, this.serverTime});

  final bool ok;
  final String message;
  final int? ms;
  final String? serverTime;
}

/// Cliente HTTP da API Unitec Entregas (`/api/v1/entregas`).
class ApiClient {
  ApiClient(this.config);

  final AppConfig config;
  final http.Client _http = http.Client();

  Duration timeout = const Duration(seconds: 20);

  Map<String, String> _headers({bool auth = false}) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (config.deviceUuid.isNotEmpty) 'X-ENT-Device': config.deviceUuid,
      if (auth && config.token.isNotEmpty) 'Authorization': 'Bearer ${config.token}',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${config.apiBase}/$path').replace(queryParameters: query);

  static Future<bool> pingBase(String baseUrl, {Duration timeout = const Duration(seconds: 2)}) async {
    final r = await pingDetailed(baseUrl, timeout: timeout);
    return r.ok;
  }

  static Future<PingResult> pingDetailed(
    String baseUrl, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse('$baseUrl/api/v1/entregas/ping');
      final r = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
      sw.stop();
      if (r.statusCode != 200) {
        return PingResult(ok: false, message: 'Respondeu HTTP ${r.statusCode}', ms: sw.elapsedMilliseconds);
      }
      final body = jsonDecode(r.body);
      final okBody = body is Map && (body['ok'] == true || body['server_time'] != null);
      return PingResult(
        ok: okBody,
        message: okBody ? 'OK' : 'Resposta inesperada do servidor',
        ms: sw.elapsedMilliseconds,
        serverTime: body is Map ? body['server_time']?.toString() : null,
      );
    } on TimeoutException {
      sw.stop();
      return PingResult(ok: false, message: 'Tempo esgotado', ms: sw.elapsedMilliseconds);
    } catch (e) {
      sw.stop();
      return PingResult(ok: false, message: e.toString(), ms: sw.elapsedMilliseconds);
    }
  }

  Future<bool> ping() async {
    try {
      final r = await _http.get(_uri('ping'), headers: _headers()).timeout(timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> registerDevice({
    String? deviceName,
    String platform = 'android',
    String appVersion = kAppVersion,
  }) async {
    final r = await _http
        .post(
          _uri('devices/register'),
          headers: _headers(),
          body: jsonEncode({
            'device_uuid': config.deviceUuid,
            'device_name': deviceName ?? config.deviceName,
            'platform': platform,
            'app_version': appVersion,
          }),
        )
        .timeout(timeout);
    return _decode(r);
  }

  Future<Map<String, dynamic>> deviceStatus() async {
    final r = await _http
        .get(_uri('devices/status', {'device_uuid': config.deviceUuid}), headers: _headers())
        .timeout(timeout);
    return _decode(r);
  }

  Future<Map<String, dynamic>> info() async {
    final r = await _http.get(_uri('info'), headers: _headers()).timeout(timeout);
    return _decode(r);
  }

  Future<List<dynamic>> usuarios(int empresaId) async {
    final r = await _http
        .get(_uri('users', {'empresa_id': '$empresaId'}), headers: _headers())
        .timeout(timeout);
    final data = _decode(r);
    return (data['users'] as List<dynamic>? ?? []);
  }

  Future<Map<String, dynamic>> login({
    required int empresaId,
    required int userId,
    required String senha,
    required String deviceUuid,
    String? deviceName,
  }) async {
    final r = await _http
        .post(
          _uri('auth/login'),
          headers: _headers(),
          body: jsonEncode({
            'empresa_id': empresaId,
            'user_id': userId,
            'senha': senha,
            'device_uuid': deviceUuid,
            'device_name': deviceName,
            'platform': 'android',
            'app_version': kAppVersion,
          }),
        )
        .timeout(timeout);
    return _decode(r);
  }

  Future<void> logout() async {
    try {
      await _http.post(_uri('auth/logout'), headers: _headers(auth: true)).timeout(timeout);
    } catch (_) {}
  }

  /// Pull de cargas fechadas do entregador autenticado.
  Future<Map<String, dynamic>> syncPull() async {
    final r = await _http
        .get(_uri('sync/pull'), headers: _headers(auth: true))
        .timeout(const Duration(seconds: 40));
    return _decode(r);
  }

  /// Push de conclusão de entrega (multipart: foto/assinatura/itens opcionais).
  Future<Map<String, dynamic>> syncPushEntrega({
    required String appLocalUuid,
    required int cargaId,
    required int pedidoId,
    required String status,
    String? fotoPath,
    String? assinaturaPath,
    String? motivoNaoEntrega,
    String? observacao,
    String? concluidaEm,
    List<Map<String, dynamic>>? itens,
  }) async {
    final uri = _uri('sync/push');
    final req = http.MultipartRequest('POST', uri);
    req.headers.addAll({
      'Accept': 'application/json',
      if (config.deviceUuid.isNotEmpty) 'X-ENT-Device': config.deviceUuid,
      if (config.token.isNotEmpty) 'Authorization': 'Bearer ${config.token}',
    });
    req.fields['app_local_uuid'] = appLocalUuid;
    req.fields['carga_id'] = '$cargaId';
    req.fields['pedido_id'] = '$pedidoId';
    req.fields['status'] = status;
    if (motivoNaoEntrega != null && motivoNaoEntrega.isNotEmpty) {
      req.fields['motivo_nao_entrega'] = motivoNaoEntrega;
    }
    if (observacao != null && observacao.isNotEmpty) {
      req.fields['observacao'] = observacao;
    }
    if (concluidaEm != null && concluidaEm.isNotEmpty) {
      req.fields['concluida_em'] = concluidaEm;
    }
    if (fotoPath != null && fotoPath.isNotEmpty) {
      req.files.add(await http.MultipartFile.fromPath('foto', fotoPath));
    }
    if (assinaturaPath != null && assinaturaPath.isNotEmpty) {
      req.files.add(await http.MultipartFile.fromPath('assinatura', assinaturaPath));
    }
    if (itens != null && itens.isNotEmpty) {
      req.fields['itens'] = jsonEncode(itens);
    }

    final streamed = await req.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    final fake = http.Response(body, streamed.statusCode, headers: streamed.headers);
    return _decode(fake);
  }

  Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(r.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (r.statusCode >= 200 && r.statusCode < 300) {
      return body ?? <String, dynamic>{};
    }

    final message = (body?['message'] ??
            body?['error'] ??
            (body?['errors'] is Map
                ? (body!['errors'] as Map).values.expand((v) => v is List ? v : [v]).join(' ')
                : null) ??
            'Erro HTTP ${r.statusCode}')
        .toString();

    throw ApiException(
      message,
      statusCode: r.statusCode,
      code: body?['code']?.toString(),
    );
  }
}
