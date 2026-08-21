// test/fakes/fake_point_store.dart

import 'dart:typed_data';

import 'package:mapfi/models/outbox_entry.dart';
import 'package:mapfi/models/wifi_point.dart';
import 'package:mapfi/services/point_store.dart';

/// Простая in-memory реализация PointStore для тестов.
class FakePointStore implements PointStore {
  final List<WiFiPoint> points = [];
  final Map<int, DateTime> syncState = {};
  final List<OutboxEntry> outbox = [];
  int _nextOutboxId = 1;

  @override
  Future<List<WiFiPoint>> loadPoints() async => List.unmodifiable(points);

  @override
  List<WiFiPoint> parseFromBytes(Uint8List bytes) => throw UnimplementedError();

  @override
  Future<void> savePoints(List<WiFiPoint> newPoints) async {
    points
      ..clear()
      ..addAll(newPoints);
  }

  @override
  Future<void> upsertPoint(WiFiPoint point) async {
    final index = points.indexWhere((p) => p.id == point.id);
    if (index >= 0) {
      points[index] = point;
    } else {
      points.add(point);
    }
  }

  @override
  Future<void> upsertPoints(Iterable<WiFiPoint> newPoints) async {
    for (final p in newPoints) {
      await upsertPoint(p);
    }
  }

  @override
  Future<void> removePoint(String id) async {
    points.removeWhere((p) => p.id == id);
  }

  @override
  Future<DateTime?> lastSync(int regionId) async => syncState[regionId];

  @override
  Future<void> setLastSync(int regionId, DateTime time) async {
    syncState[regionId] = time;
  }

  @override
  Future<void> enqueueOutbox(OutboxEntry entry) async {
    outbox.add(entry.copyWith(id: _nextOutboxId++));
  }

  @override
  Future<List<OutboxEntry>> pendingOutbox() async => List.unmodifiable(outbox);

  @override
  Future<void> removeOutbox(int id) async {
    outbox.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> close() async {}
}