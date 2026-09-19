import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:unitec_entregas/db/local_db.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.overrideDbFileName = 'unitec_entregas_upsert_test.db';
  });

  tearDownAll(() async {
    await LocalDb.instance.resetForTests();
    LocalDb.overrideDbFileName = null;
  });

  setUp(() async {
    await LocalDb.instance.resetForTests();
  });

  test('upsert cargas não duplica carga/pedido/item', () async {
    final db = LocalDb.instance;

    final carga = {
      'id': 15,
      'numero': '15',
      'data': '2026-09-18',
      'motorista': 'Transportadora X',
      'veiculo': 'ABC1D23',
      'observacao': null,
      'status': 'fechada',
      'pedidos': [
        {
          'pedido_id': 1250,
          'numero': '1250',
          'cliente': 'Mercado Central',
          'documento': '12.345.678/0001-90',
          'telefone': '47999999999',
          'endereco': 'Rua X, 123',
          'valor_total': 850.0,
          'observacao': null,
          'itens': [
            {
              'produto_id': 1,
              'codigo': 'P1',
              'descricao': 'Produto A',
              'quantidade': 2.0,
              'unidade': 'UN',
            },
          ],
        },
      ],
    };

    await db.upsertCargasFromPull([carga]);
    await db.upsertCargasFromPull([carga]);

    expect(await db.countCargas(), 1);
    expect(await db.countPedidos(), 1);
    expect(await db.countItens(), 1);

    final pedidos = await db.listPedidos(15);
    expect(pedidos.first['cliente'], 'Mercado Central');
    expect(pedidos.first['endereco'], 'Rua X, 123');

    final itens = await db.listItens(15, 1250);
    expect(itens.first['descricao'], 'Produto A');
    expect((itens.first['quantidade'] as num).toDouble(), 2.0);
  });
}
