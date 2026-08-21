// lib/services/point_store_stub.dart
// In-memory реализация PointStore для web (режим просмотра).

import 'dart:typed_data';

import '../models/outbox_entry.dart';
import '../models/wifi_point.dart';
import 'json_point_parser.dart';
import 'point_store.dart';

class InMemoryPointStore implements PointStore {
  final List<WiFiPoint> _points = [];
  final Map<int, DateTime> _syncState = {};
  final List<OutboxEntry> _outbox = [];
  int _nextOutboxId = 1;

  @override
  Future<List<WiFiPoint>> loadPoints() async => List.unmodifiable(_points);

  @override
  List<WiFiPoint> parseFromBytes(Uint8List bytes) =>
      JsonPointParser.parsePoints(bytes);

  @override
  Future<void> savePoints(List<WiFiPoint> points) async {
    _points
      ..clear()
      ..addAll(points);
  }

  @override
  Future<void> upsertPoint(WiFiPoint point) async {
    final index = _points.indexWhere((p) => p.id == point.id);
    if (index >= 0) {
      _points[index] = point;
    } else {
      _points.add(point);
    }
  }

  @override
  Future<void> upsertPoints(Iterable<WiFiPoint> points) async {
    for (final pt in points) {
      await upsertPoint(pt);
    }
  }

  @override
  Future<void> removePoint(String id) async {
    _points.removeWhere((p) => p.id == id);
  }

  @override
  Future<DateTime?> lastSync(int regionId) async => _syncState[regionId];

  @override
  Future<void> setLastSync(int regionId, DateTime time) async {
    _syncState[regionId] = time;
  }

  @override
  Future<void> enqueueOutbox(OutboxEntry entry) async {
    _outbox.add(entry.copyWith(id: _nextOutboxId++));
  }

  @override
  Future<List<OutboxEntry>> pendingOutbox() async => List.unmodifiable(_outbox);

  @override
  Future<void> removeOutbox(int id) async {
    _outbox.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> close() async {}
}

PointStore createPointStore() => InMemoryPointStore();