// lib/services/point_store_io.dart
// SQLite-реализация PointStore для io-платформ (Android/iOS/Desktop).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqf;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/outbox_entry.dart';
import '../models/wifi_point.dart';
import 'json_point_parser.dart';
import 'point_store.dart';

/// Хранилище точек на базе SQLite.
///
/// Таблицы:
/// - `points` — точки (id, ssid, password, lat, lng, region_id,
///   dataset_type, is_deleted, updated_at)
/// - `sync_state` — watermark последней синхронизации по регионам
/// - `pending_outbox` — очередь оффлайн-отправок
class SqlitePointStore implements PointStore {
  static const int _dbVersion = 1;

  final DatabaseFactory? _factory;
  final String? _databasePath;
  final String? _legacyJsonPath;

  sqf.Database? _db;

  SqlitePointStore({
    DatabaseFactory? factory,
    String? databasePath,
    String? legacyJsonPath,
  })  : _factory = factory,
        _databasePath = databasePath,
        _legacyJsonPath = legacyJsonPath;

  Future<sqf.Database> get _database async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;

    final db = await _open();
    _db = db;
    await _migrateLegacyJsonIfNeeded();
    return db;
  }

  Future<sqf.Database> _open() async {
    final factory = _factory;
    if (factory != null) {
      return factory.openDatabase(
        _databasePath ?? inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: _dbVersion, onCreate: _onCreate),
      );
    }

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      return databaseFactoryFfi.openDatabase(
        _databasePath ?? 'mapfi.db',
        options: OpenDatabaseOptions(version: _dbVersion, onCreate: _onCreate),
      );
    }

    // Android / iOS / macOS
    final dir = await getApplicationDocumentsDirectory();
    final path = _databasePath ?? p.join(dir.path, 'mapfi.db');
    return sqf.openDatabase(path, version: _dbVersion, onCreate: _onCreate);
  }

  Future<void> _onCreate(sqf.Database db, int version) async {
    await db.execute('''
      CREATE TABLE points (
        id TEXT PRIMARY KEY,
        ssid TEXT NOT NULL,
        password TEXT NOT NULL DEFAULT '',
        rating REAL NOT NULL DEFAULT 0,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        region_id INTEGER NOT NULL DEFAULT 0,
        dataset_type TEXT NOT NULL DEFAULT 'public',
        is_deleted INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_points_region ON points(region_id)');
    await db.execute(
        'CREATE INDEX idx_points_deleted ON points(is_deleted)');

    await db.execute('''
      CREATE TABLE sync_state (
        region_id INTEGER PRIMARY KEY,
        last_sync TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  /// Одноразовый перенос данных из старого points.json при первом запуске.
  Future<void> _migrateLegacyJsonIfNeeded() async {
    final db = _db;
    if (db == null) return;

    final count = sqf.Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM points'),
    );
    if (count != null && count > 0) return;

    final legacyPath = _legacyJsonPath;
    if (legacyPath == null) return;

    final file = File(legacyPath);
    if (!file.existsSync()) return;

    try {
      final bytes = file.readAsBytesSync();
      final points = JsonPointParser.parsePoints(bytes);
      final batch = db.batch();
      for (final pt in points) {
        batch.insert('points', _toRow(pt));
      }
      await batch.commit(noResult: true);
    } catch (_) {
      // Повреждённый legacy-файл — не блокируем запуск приложения.
    }
  }

  // --- CRUD ---

  @override
  Future<List<WiFiPoint>> loadPoints() async {
    final db = await _database;
    final rows = await db.query(
      'points',
      where: 'is_deleted = 0',
      orderBy: 'ssid COLLATE NOCASE ASC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  List<WiFiPoint> parseFromBytes(bytes) => JsonPointParser.parsePoints(bytes);

  @override
  Future<void> savePoints(List<WiFiPoint> points) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('points');
      final batch = txn.batch();
      for (final pt in points) {
        batch.insert('points', _toRow(pt));
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> upsertPoint(WiFiPoint point) async {
    final db = await _database;
    await db.insert(
      'points',
      _toRow(point),
      conflictAlgorithm: sqf.ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> upsertPoints(Iterable<WiFiPoint> points) async {
    final db = await _database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final pt in points) {
        batch.insert(
          'points',
          _toRow(pt),
          conflictAlgorithm: sqf.ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> removePoint(String id) async {
    final db = await _database;
    await db.delete('points', where: 'id = ?', whereArgs: [id]);
  }

  // --- Sync state ---

  @override
  Future<DateTime?> lastSync(int regionId) async {
    final db = await _database;
    final rows = await db.query(
      'sync_state',
      columns: ['last_sync'],
      where: 'region_id = ?',
      whereArgs: [regionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['last_sync'] as String?;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  @override
  Future<void> setLastSync(int regionId, DateTime time) async {
    final db = await _database;
    await db.insert(
      'sync_state',
      {
        'region_id': regionId,
        'last_sync': time.toUtc().toIso8601String(),
      },
      conflictAlgorithm: sqf.ConflictAlgorithm.replace,
    );
  }

  // --- Outbox ---

  @override
  Future<void> enqueueOutbox(OutboxEntry entry) async {
    final db = await _database;
    await db.insert('pending_outbox', {
      'kind': entry.kind,
      'payload': entry.payloadJson,
      'created_at': entry.createdAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<List<OutboxEntry>> pendingOutbox() async {
    final db = await _database;
    final rows = await db.query('pending_outbox', orderBy: 'id ASC');
    return rows.map(_fromOutboxRow).toList();
  }

  @override
  Future<void> removeOutbox(int id) async {
    final db = await _database;
    await db.delete('pending_outbox', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // --- Mapping ---

  Map<String, Object?> _toRow(WiFiPoint p, {DateTime? updatedAt}) => {
        'id': p.id,
        'ssid': p.name,
        'password': p.password,
        'rating': p.rating,
        'lat': p.lat,
        'lng': p.lng,
        'region_id': p.regionId,
        'dataset_type': p.datasetType,
        'is_deleted': 0,
        'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      };

  WiFiPoint _fromRow(Map<String, Object?> row) => WiFiPoint(
        id: row['id'] as String,
        name: row['ssid'] as String,
        password: row['password'] as String,
        rating: (row['rating'] as num).toDouble(),
        lat: (row['lat'] as num).toDouble(),
        lng: (row['lng'] as num).toDouble(),
        regionId: (row['region_id'] as num).toInt(),
        datasetType: row['dataset_type'] as String,
      );

  OutboxEntry _fromOutboxRow(Map<String, Object?> row) => OutboxEntry(
        id: row['id'] as int,
        kind: row['kind'] as String,
        payload:
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

/// Создаёт SQLite-хранилище по умолчанию.
PointStore createPointStore() => SqlitePointStore();