/// Motivos de não entrega (mesmos códigos do ERP).
class MotivosNaoEntrega {
  static const clienteFechado = 'cliente_fechado';
  static const clienteAusente = 'cliente_ausente';
  static const recusou = 'recusou_mercadoria';
  static const endereco = 'endereco_nao_localizado';
  static const problema = 'problema_no_pedido';
  static const outro = 'outro';

  static const Map<String, String> labels = {
    clienteFechado: 'Cliente fechado',
    clienteAusente: 'Cliente ausente',
    recusou: 'Recusou mercadoria',
    endereco: 'Endereço não localizado',
    problema: 'Problema no pedido',
    outro: 'Outro',
  };

  static String label(String? codigo) {
    if (codigo == null || codigo.isEmpty) return '—';
    return labels[codigo] ?? codigo;
  }
}
