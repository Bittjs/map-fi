// test/point_store_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapfi/models/outbox_entry.dart';
import 'package:mapfi/models/wifi_point.dart';
import 'package:mapfi/services/point_store_io.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  SqlitePointStore makeStore({String? legacyJsonPath}) => SqlitePointStore(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
        legacyJsonPath: legacyJsonPath,
      );

  WiFiPoint point(String id, {String name = 'Net'}) => WiFiPoint(
        id: id,
        name: name,
        password: '',
        rating: 0,
        lat: 55.0,
        lng: 83.0,
      );

  group('SqlitePointStore CRUD', () {
    test('savePoints/loadPoints round-trip сохраняет все поля', () async {
      final store = makeStore();
      await store.savePoints([
        const WiFiPoint(
          id: 'a',
          name: 'Net',
          password: '1234',
          rating: 4.5,
          lat: 55.1,
          lng: 82.9,
          regionId: 54,
          datasetType: 'volunteer_test',
        ),
      ]);
      final loaded = await store.loadPoints();
      expect(loaded, hasLength(1));
      final p = loaded.first;
      expect(p.name, 'Net');
      expect(p.regionId, 54);
      expect(p.datasetType, 'volunteer_test');
      await store.close();
    });

    test('savePoints полностью заменяет список', () async {
      final store = makeStore();
      await store.savePoints([point('a')]);
      await store.savePoints([point('b'), point('c')]);
      final loaded = await store.loadPoints();
      expect(loaded.map((p) => p.id).toSet(), {'b', 'c'});
      await store.close();
    });

    test('upsertPoint обновляет запись по id', () async {
      final store = makeStore();
      await store.upsertPoint(point('a', name: 'Old'));
      await store.upsertPoint(point('a', name: 'New'));
      final loaded = await store.loadPoints();
      expect(loaded.single.name, 'New');
      await store.close();
    });

    test('removePoint удаляет точку', () async {
      final store = makeStore();
      await store.upsertPoint(point('a'));
      await store.removePoint('a');
      expect(await store.loadPoints(), isEmpty);
      await store.close();
    });
  });

  group('SqlitePointStore sync state', () {
    test('lastSync изначально null, setLastSync сохраняет время', () async {
      final store = makeStore();
      final t = DateTime.utc(2026, 1, 1, 12);
      expect(await store.lastSync(54), isNull);
      await store.setLastSync(54, t);
      expect(await store.lastSync(54), t.toUtc());
      await store.close();
    });
  });

  group('SqlitePointStore outbox', () {
    test('enqueue/pending/remove', () async {
      final store = makeStore();
      await store.enqueueOutbox(OutboxEntry(
        kind: OutboxEntry.kindPoint,
        payload: {'ssid': 'X'},
        createdAt: DateTime.utc(2026, 1, 1),
      ));
      final pending = await store.pendingOutbox();
      expect(pending, hasLength(1));
      expect(pending.first.kind, OutboxEntry.kindPoint);
      expect(pending.first.payload['ssid'], 'X');
      await store.removeOutbox(pending.first.id!);
      expect(await store.pendingOutbox(), isEmpty);
      await store.close();
    });
  });

  group('SqlitePointStore миграция из points.json', () {
    test('первый запуск импортирует legacy-файл с дефолтными region/слой', () async {
      final dir = await Directory.systemTemp.createTemp('mapfi_test');
      addTearDown(() => dir.delete(recursive: true));
      final legacy = File('${dir.path}/points.json');
      await legacy.writeAsString(jsonEncode([
        {
          'id': 'legacy-1',
          'name': 'OldNet',
          'password': '',
          'rating': 0,
          'lat': 55.0,
          'lng': 83.0,
        },
      ]));

      final store = makeStore(legacyJsonPath: legacy.path);
      final loaded = await store.loadPoints();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 'legacy-1');
      expect(loaded.first.regionId, 0,
          reason: 'в старом файле нет region_id → 0');
      expect(loaded.first.datasetType, 'public');
      await store.close();
    });

    test('повторное открытие БД не дублирует legacy-точки', () async {
      final dir = await Directory.systemTemp.createTemp('mapfi_test');
      addTearDown(() => dir.delete(recursive: true));
      final dbPath = '${dir.path}/mapfi.db';
      final legacy = File('${dir.path}/points.json');
      await legacy.writeAsString(jsonEncode([
        {
          'id': 'legacy-1',
          'name': 'OldNet',
          'password': '',
          'rating': 0,
          'lat': 55.0,
          'lng': 83.0,
        },
      ]));

      SqlitePointStore open() => SqlitePointStore(
            factory: databaseFactoryFfi,
            databasePath: dbPath,
            legacyJsonPath: legacy.path,
          );

      final store1 = open();
      expect(await store1.loadPoints(), hasLength(1));
      await store1.close();

      final store2 = open();
      expect(await store2.loadPoints(), hasLength(1),
          reason: 'точки уже в БД — повторный импорт не выполняется');
      await store2.close();
    });
  });
}