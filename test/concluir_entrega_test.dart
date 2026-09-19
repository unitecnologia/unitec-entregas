import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unitec_entregas/db/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.overrideDbFileName = 'unitec_entregas_concluir_test.db';
  });

  tearDownAll(() async {
    await LocalDb.instance.resetForTests();
    LocalDb.overrideDbFileName = null;
  });

  setUp(() async {
    await LocalDb.instance.resetForTests();
  });

  test('concluir entrega local cria fila e não duplica', () async {
    final db = LocalDb.instance;

    final permanente = p.join(
      Directory.systemTemp.path,
      'entregas_test',
      '15',
      '1250',
      'foto.jpg',
    );
    await Directory(p.dirname(permanente)).create(recursive: true);
    await File(permanente).writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);

    final e1 = await db.concluirEntregaLocal(
      cargaId: 15,
      pedidoId: 1250,
      status: 'entregue',
      fotoPath: permanente,
      observacao: 'Portaria',
    );

    expect(e1['status'], 'entregue');
    expect(e1['sync_status'], 'pendente');
    expect(e1['app_local_uuid'], isNotEmpty);
    expect(e1['foto_path'], permanente);
    expect(await db.countEntregas(), 1);

    final queue = await db.pendingQueueItems();
    expect(queue.length, 1);
    expect(queue.first['entity_type'], 'entrega');

    expect(
      () => db.concluirEntregaLocal(
        cargaId: 15,
        pedidoId: 1250,
        status: 'entregue',
        fotoPath: permanente,
      ),
      throwsStateError,
    );
    expect(await db.countEntregas(), 1);

    await db.markEntregaSincronizada(
      appLocalUuid: e1['app_local_uuid'] as String,
      queueId: queue.first['id'] as int,
    );
    final e2 = await db.getEntrega(15, 1250);
    expect(e2!['sync_status'], 'sincronizado');
    expect(File(permanente).existsSync(), isTrue);
  });

  test('concluir entregue sem foto nem assinatura', () async {
    final db = LocalDb.instance;

    final e = await db.concluirEntregaLocal(
      cargaId: 30,
      pedidoId: 300,
      status: 'entregue',
      observacao: 'Sem comprovante',
    );

    expect(e['status'], 'entregue');
    expect(e['foto_path'], isNull);
    expect(e['assinatura_path'], isNull);
    expect(e['sync_status'], 'pendente');
    expect(await db.countEntregas(), 1);
    expect((await db.pendingQueueItems()).length, 1);
  });

  test('concluir entregue só com assinatura', () async {
    final db = LocalDb.instance;
    final permanente = p.join(
      Directory.systemTemp.path,
      'entregas_test',
      '31',
      '301',
      'assinatura.png',
    );
    await Directory(p.dirname(permanente)).create(recursive: true);
    await File(permanente).writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

    final e = await db.concluirEntregaLocal(
      cargaId: 31,
      pedidoId: 301,
      status: 'entregue',
      assinaturaPath: permanente,
    );

    expect(e['status'], 'entregue');
    expect(e['foto_path'], isNull);
    expect(e['assinatura_path'], permanente);
    expect(File(permanente).existsSync(), isTrue);
  });

  test('concluir parcial com quantidade reduzida', () async {
    final db = LocalDb.instance;

    final e = await db.concluirEntregaLocal(
      cargaId: 40,
      pedidoId: 400,
      status: 'parcial',
      itens: [
        {
          'produto_id': 1,
          'codigo': '2261',
          'descricao': 'COCA',
          'unidade': 'UN',
          'quantidade_original': 2,
          'quantidade': 1,
        },
      ],
    );

    expect(e['status'], 'parcial');
    expect(e['itens_json'], contains('2261'));
    final queue = await db.pendingQueueItems();
    expect(queue.length, 1);
    expect(queue.first['payload'], contains('parcial'));
  });

  test('nao entregue local entra na fila sem foto', () async {
    final db = LocalDb.instance;

    final e = await db.concluirEntregaLocal(
      cargaId: 20,
      pedidoId: 200,
      status: 'nao_entregue',
      motivoNaoEntrega: 'cliente_fechado',
      observacao: null,
    );

    expect(e['status'], 'nao_entregue');
    expect(e['motivo_nao_entrega'], 'cliente_fechado');
    expect(e['sync_status'], 'pendente');
    expect(e['foto_path'], isNull);
    expect(await db.countEntregas(), 1);
    expect((await db.pendingQueueItems()).length, 1);
  });
}
