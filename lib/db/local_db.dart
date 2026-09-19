import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// SQLite local Unitec Entregas (offline-first).
class LocalDb {
  LocalDb._();

  static final LocalDb instance = LocalDb._();

  /// Nome do arquivo SQLite (só para testes isolarem paralelismo).
  static String? overrideDbFileName;

  Database? _db;

  Future<void> resetForTests() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    final dir = await getDatabasesPath();
    final name = overrideDbFileName ?? 'unitec_entregas.db';
    final path = p.join(dir, name);
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      final f = File('$path$suffix');
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final name = overrideDbFileName ?? 'unitec_entregas.db';
    final path = p.join(dir, name);

    return openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await _createV1(db);
        await _createV2(db);
        await _createV3(db);
        await _createV4(db);
        await _createV5(db);
        await _createV6(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createV2(db);
        if (oldVersion < 3) await _createV3(db);
        if (oldVersion < 4) await _createV4(db);
        if (oldVersion < 5) await _createV5(db);
        if (oldVersion < 6) await _createV6(db);
      },
    );
  }

  Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_meta (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        payload TEXT,
        status TEXT NOT NULL DEFAULT 'pendente',
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
  }

  Future<void> _createV2(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cargas (
        id INTEGER PRIMARY KEY NOT NULL,
        numero TEXT NOT NULL,
        data TEXT,
        motorista TEXT,
        veiculo TEXT,
        observacao TEXT,
        status TEXT NOT NULL,
        qtd_pedidos INTEGER NOT NULL DEFAULT 0,
        synced_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS carga_pedidos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        carga_id INTEGER NOT NULL,
        pedido_id INTEGER NOT NULL,
        numero TEXT,
        cliente TEXT,
        documento TEXT,
        telefone TEXT,
        endereco TEXT,
        valor_total REAL NOT NULL DEFAULT 0,
        observacao TEXT,
        UNIQUE(carga_id, pedido_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS carga_pedido_itens (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        carga_id INTEGER NOT NULL,
        pedido_id INTEGER NOT NULL,
        produto_id INTEGER,
        codigo TEXT,
        descricao TEXT,
        quantidade REAL NOT NULL DEFAULT 0,
        unidade TEXT,
        UNIQUE(carga_id, pedido_id, produto_id, codigo, descricao)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_carga_pedidos_carga ON carga_pedidos(carga_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_carga_itens_pedido ON carga_pedido_itens(carga_id, pedido_id)');
  }

  Future<void> _createV3(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS entregas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        app_local_uuid TEXT NOT NULL UNIQUE,
        carga_id INTEGER NOT NULL,
        pedido_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'entregue',
        motivo_nao_entrega TEXT,
        observacao TEXT,
        foto_path TEXT,
        concluida_em TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pendente',
        synced_at TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(carga_id, pedido_id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_entregas_sync ON entregas(sync_status)');
  }

  Future<void> _createV4(Database db) async {
    // Upgrade de v3: adiciona motivo se a tabela antiga não tinha a coluna.
    final info = await db.rawQuery('PRAGMA table_info(entregas)');
    final hasMotivo = info.any((c) => c['name'] == 'motivo_nao_entrega');
    if (!hasMotivo) {
      await db.execute('ALTER TABLE entregas ADD COLUMN motivo_nao_entrega TEXT');
    }
  }

  Future<void> _createV5(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(entregas)');
    final hasAssinatura = info.any((c) => c['name'] == 'assinatura_path');
    if (!hasAssinatura) {
      await db.execute('ALTER TABLE entregas ADD COLUMN assinatura_path TEXT');
    }
  }

  Future<void> _createV6(Database db) async {
    final info = await db.rawQuery('PRAGMA table_info(entregas)');
    final hasItens = info.any((c) => c['name'] == 'itens_json');
    if (!hasItens) {
      await db.execute('ALTER TABLE entregas ADD COLUMN itens_json TEXT');
    }
  }

  Future<void> setMeta(String key, String? value) async {
    final db = await database;
    await db.insert(
      'sync_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getMeta(String key) async {
    final db = await database;
    final rows = await db.query('sync_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Copia foto da câmera para armazenamento permanente do app.
  Future<String> persistFoto({
    required String tempPath,
    required int cargaId,
    required int pedidoId,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'entregas', '$cargaId', '$pedidoId'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final name = '${const Uuid().v4()}.jpg';
    final dest = p.join(dir.path, name);
    await File(tempPath).copy(dest);
    return dest;
  }

  /// Grava PNG de assinatura no armazenamento permanente do app.
  Future<String> persistAssinaturaBytes({
    required List<int> bytes,
    required int cargaId,
    required int pedidoId,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'entregas', '$cargaId', '$pedidoId'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final dest = p.join(dir.path, '${const Uuid().v4()}.png');
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  }

  /// Grava conclusão local + fila de sync de forma atômica.
  Future<Map<String, dynamic>> concluirEntregaLocal({
    required int cargaId,
    required int pedidoId,
    required String status,
    String? fotoPath,
    String? assinaturaPath,
    String? motivoNaoEntrega,
    String? observacao,
    List<Map<String, dynamic>>? itens,
  }) async {
    final db = await database;
    final existing = await getEntrega(cargaId, pedidoId);
    if (existing != null) {
      throw StateError('Pedido já possui ocorrência registrada.');
    }

    final uuid = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final itensJson = itens == null || itens.isEmpty ? null : jsonEncode(itens);

    await db.transaction((txn) async {
      final entregaId = await txn.insert('entregas', {
        'app_local_uuid': uuid,
        'carga_id': cargaId,
        'pedido_id': pedidoId,
        'status': status,
        'motivo_nao_entrega': motivoNaoEntrega,
        'observacao': observacao,
        'foto_path': fotoPath,
        'assinatura_path': assinaturaPath,
        'itens_json': itensJson,
        'concluida_em': now,
        'sync_status': 'pendente',
        'synced_at': null,
        'created_at': now,
      });

      await txn.insert('sync_queue', {
        'entity_type': 'entrega',
        'entity_id': uuid,
        'payload': jsonEncode({
          'entrega_id': entregaId,
          'app_local_uuid': uuid,
          'carga_id': cargaId,
          'pedido_id': pedidoId,
          'foto_path': fotoPath,
          'assinatura_path': assinaturaPath,
          'motivo_nao_entrega': motivoNaoEntrega,
          'observacao': observacao,
          'concluida_em': now,
          'status': status,
          'itens': itens ?? [],
        }),
        'status': 'pendente',
        'attempts': 0,
        'last_error': null,
        'created_at': now,
        'updated_at': now,
      });
    });

    return (await getEntrega(cargaId, pedidoId))!;
  }

  Future<Map<String, dynamic>?> getEntrega(int cargaId, int pedidoId) async {
    final db = await database;
    final rows = await db.query(
      'entregas',
      where: 'carga_id = ? AND pedido_id = ?',
      whereArgs: [cargaId, pedidoId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> getEntregaByUuid(String uuid) async {
    final db = await database;
    final rows = await db.query(
      'entregas',
      where: 'app_local_uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<int, Map<String, dynamic>>> entregasDaCarga(int cargaId) async {
    final db = await database;
    final rows = await db.query('entregas', where: 'carga_id = ?', whereArgs: [cargaId]);
    final map = <int, Map<String, dynamic>>{};
    for (final r in rows) {
      final pid = _asInt(r['pedido_id']);
      if (pid != null) map[pid] = r;
    }
    return map;
  }

  Future<int> countEntregasCarga(int cargaId) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM entregas WHERE carga_id = ? AND status = ?',
      [cargaId, 'entregue'],
    );
    return _asInt(r.first['c']) ?? 0;
  }

  Future<List<Map<String, dynamic>>> pendingQueueItems({int limit = 20}) async {
    final db = await database;
    return db.query(
      'sync_queue',
      where: "status IN ('pendente','erro') AND entity_type = ?",
      whereArgs: ['entrega'],
      orderBy: 'id ASC',
      limit: limit,
    );
  }

  Future<void> markQueueSyncing(int queueId) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.update(
      'sync_queue',
      {'status': 'sincronizando', 'updated_at': now},
      where: 'id = ?',
      whereArgs: [queueId],
    );
  }

  Future<void> markEntregaSincronizada({
    required String appLocalUuid,
    required int queueId,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'entregas',
        {'sync_status': 'sincronizado', 'synced_at': now},
        where: 'app_local_uuid = ?',
        whereArgs: [appLocalUuid],
      );
      await txn.update(
        'sync_queue',
        {'status': 'sincronizado', 'updated_at': now, 'last_error': null},
        where: 'id = ?',
        whereArgs: [queueId],
      );
    });
  }

  Future<void> markEntregaErro({
    required String appLocalUuid,
    required int queueId,
    required String error,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE sync_queue SET status = ?, attempts = attempts + 1, last_error = ?, updated_at = ? WHERE id = ?',
        ['erro', error, now, queueId],
      );
      await txn.update(
        'entregas',
        {'sync_status': 'erro'},
        where: 'app_local_uuid = ? AND sync_status != ?',
        whereArgs: [appLocalUuid, 'sincronizado'],
      );
    });
  }

  Future<void> upsertCargasFromPull(List<Map<String, dynamic>> cargas) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final c in cargas) {
        final cargaId = _asInt(c['id']);
        if (cargaId == null) continue;

        final pedidos = (c['pedidos'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        await txn.insert(
          'cargas',
          {
            'id': cargaId,
            'numero': (c['numero'] ?? '').toString(),
            'data': c['data']?.toString(),
            'motorista': c['motorista']?.toString(),
            'veiculo': c['veiculo']?.toString(),
            'observacao': c['observacao']?.toString(),
            'status': (c['status'] ?? 'fechada').toString(),
            'qtd_pedidos': pedidos.length,
            'synced_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await txn.delete('carga_pedido_itens', where: 'carga_id = ?', whereArgs: [cargaId]);
        await txn.delete('carga_pedidos', where: 'carga_id = ?', whereArgs: [cargaId]);

        for (final pedido in pedidos) {
          final pedidoId = _asInt(pedido['pedido_id']);
          if (pedidoId == null) continue;

          await txn.insert(
            'carga_pedidos',
            {
              'carga_id': cargaId,
              'pedido_id': pedidoId,
              'numero': pedido['numero']?.toString(),
              'cliente': pedido['cliente']?.toString(),
              'documento': pedido['documento']?.toString(),
              'telefone': pedido['telefone']?.toString(),
              'endereco': pedido['endereco']?.toString(),
              'valor_total': _asDouble(pedido['valor_total']) ?? 0,
              'observacao': pedido['observacao']?.toString(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          final itens = (pedido['itens'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();

          for (final it in itens) {
            await txn.insert(
              'carga_pedido_itens',
              {
                'carga_id': cargaId,
                'pedido_id': pedidoId,
                'produto_id': _asInt(it['produto_id']),
                'codigo': it['codigo']?.toString(),
                'descricao': it['descricao']?.toString(),
                'quantidade': _asDouble(it['quantidade']) ?? 0,
                'unidade': it['unidade']?.toString(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    });

    await setMeta('last_pull_at', now);
  }

  Future<List<Map<String, dynamic>>> listCargas() async {
    final db = await database;
    return db.query('cargas', orderBy: 'data DESC, id DESC');
  }

  Future<Map<String, dynamic>?> getCarga(int id) async {
    final db = await database;
    final rows = await db.query('cargas', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> listPedidos(int cargaId) async {
    final db = await database;
    return db.query('carga_pedidos', where: 'carga_id = ?', whereArgs: [cargaId], orderBy: 'numero ASC');
  }

  Future<Map<String, dynamic>?> getPedido(int cargaId, int pedidoId) async {
    final db = await database;
    final rows = await db.query(
      'carga_pedidos',
      where: 'carga_id = ? AND pedido_id = ?',
      whereArgs: [cargaId, pedidoId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> listItens(int cargaId, int pedidoId) async {
    final db = await database;
    return db.query(
      'carga_pedido_itens',
      where: 'carga_id = ? AND pedido_id = ?',
      whereArgs: [cargaId, pedidoId],
      orderBy: 'id ASC',
    );
  }

  Future<int> countCargas() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM cargas');
    return _asInt(r.first['c']) ?? 0;
  }

  Future<int> countPedidos() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM carga_pedidos');
    return _asInt(r.first['c']) ?? 0;
  }

  Future<int> countItens() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM carga_pedido_itens');
    return _asInt(r.first['c']) ?? 0;
  }

  Future<int> countEntregas() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM entregas');
    return _asInt(r.first['c']) ?? 0;
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }
}
