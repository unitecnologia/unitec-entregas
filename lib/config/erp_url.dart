/// Normalização da URL do ERP (Unitec Entregas).
/// Túnel Cloudflare / unierp.uk: HTTPS sem porta 8000/8765.
/// IP local: http + porta 8765 se omitida.
class ErpUrl {
  static const hostsNuvem = [
    'trycloudflare.com',
    'cfargotunnel.com',
    'unierp.uk',
  ];

  static const int portaLocalPadrao = 8765;

  static String normalize(String raw, {int defaultPort = portaLocalPadrao}) {
    var texto = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (texto.isEmpty) return '';

    if (!texto.contains('://')) {
      final host = _hostDe(texto);
      texto = '${_esquemaPara(host)}://$texto';
    }

    var uri = Uri.tryParse(texto);
    if (uri == null || uri.host.isEmpty) return texto;

    final host = uri.host;
    final publico = ehNuvem(host) || !_ehLocal(host);
    var scheme = uri.scheme;
    var port = uri.hasPort ? uri.port : null;

    if (publico) {
      scheme = 'https';
      if (port != null && port != 443) {
        port = null;
      }
    } else if (port == null) {
      port = defaultPort;
      if (scheme != 'http' && scheme != 'https') {
        scheme = 'http';
      }
    }

    return Uri(
      scheme: scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: host,
      port: port,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    ).toString().replaceAll(RegExp(r'/+$'), '');
  }

  static bool ehNuvem(String host) {
    final h = host.toLowerCase();
    for (final dominio in hostsNuvem) {
      if (h == dominio || h.endsWith('.$dominio')) return true;
    }
    return false;
  }

  static String _esquemaPara(String host) {
    if (ehNuvem(host) || !_ehLocal(host)) return 'https';
    return 'http';
  }

  static bool _ehLocal(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '127.0.0.1' || h == '10.0.2.2' || h == '0.0.0.0') {
      return true;
    }
    final partes = h.split('.');
    if (partes.length != 4) return false;
    final a = int.tryParse(partes[0]);
    final b = int.tryParse(partes[1]);
    if (a == null || b == null) return false;
    if (a == 10 || a == 127) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  static String _hostDe(String semEsquema) {
    final semPath = semEsquema.split('/').first;
    return semPath.split(':').first;
  }
}
