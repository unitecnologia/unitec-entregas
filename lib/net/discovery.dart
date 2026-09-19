import 'dart:async';
import 'dart:io';

import '../api/api_client.dart';

/// Descoberta do ERP na LAN (TCP + ping /api/v1/entregas/ping).
class ServerDiscovery {
  static const List<int> defaultPorts = [8765, 8000];
  static const int batchSize = 16;

  static Future<String?> find({
    List<int> ports = defaultPorts,
    void Function(int done, int total)? onProgress,
  }) async {
    final prefixes = await _localPrefixes();
    if (prefixes.isEmpty) return null;

    for (final prefix in prefixes) {
      final found = await _scanSubnet(prefix, ports, onProgress);
      if (found != null) return found;
    }
    return null;
  }

  static Future<List<String>> _localPrefixes() async {
    final prefixes = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (_isPrivateIpv4(ip)) {
            final parts = ip.split('.');
            if (parts.length == 4) {
              prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
            }
          }
        }
      }
    } catch (_) {}
    return prefixes.toList();
  }

  static bool _isPrivateIpv4(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    final m = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
    if (m != null) {
      final second = int.tryParse(m.group(1) ?? '') ?? 0;
      return second >= 16 && second <= 31;
    }
    return false;
  }

  static Future<String?> _scanSubnet(
    String prefix,
    List<int> ports,
    void Function(int done, int total)? onProgress,
  ) async {
    const total = 254;
    var done = 0;

    for (var start = 1; start <= total; start += batchSize) {
      final end = (start + batchSize - 1).clamp(1, total);
      final futures = <Future<String?>>[];

      for (var host = start; host <= end; host++) {
        futures.add(_probeHost('$prefix.$host', ports));
      }

      final results = await Future.wait(futures);
      done += (end - start + 1);
      onProgress?.call(done, total);

      for (final r in results) {
        if (r != null) return r;
      }
    }
    return null;
  }

  static Future<String?> _probeHost(String ip, List<int> ports) async {
    for (final port in ports) {
      final aberto = await _tcpOpen(ip, port, const Duration(milliseconds: 600));
      if (!aberto) continue;
      final base = 'http://$ip:$port';
      final ok = await ApiClient.pingBase(base, timeout: const Duration(seconds: 2));
      if (ok) return base;
    }
    return null;
  }

  static Future<bool> _tcpOpen(String host, int port, Duration timeout) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }
}
