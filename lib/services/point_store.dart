// lib/services/point_store.dart
// Абстракция локального хранилища точек.

import 'dart:typed_data';

import '../models/outbox_entry.dart';
import '../models/wifi_point.dart';

/// Локальное хранилище точек и метаданных синхронизации.
///
/// Реализации:
/// - SQLite (io-платформы): [SqlitePointStore] в point_store_io.dart
/// - in-memory (web): [InMemoryPointStore] в point_store_stub.dart
abstract class PointStore {
  /// Все не удалённые локальные точки.
  Future<List<WiFiPoint>> loadPoints();

  /// Парсинг точек из сырых байтов JSON (импорт файлов).
  List<WiFiPoint> parseFromBytes(Uint8List bytes);

  /// Полная замена списка точек (семантика старого points.json).
  Future<void> savePoints(List<WiFiPoint> points);

  /// Вставка/обновление одной точки по id.
  Future<void> upsertPoint(WiFiPoint point);

  /// Вставка/обновление нескольких точек по id.
  Future<void> upsertPoints(Iterable<WiFiPoint> points);

  /// Жёсткое удаление точки.
  Future<void> removePoint(String id);

  /// Время последней успешной синхронизации региона (null, если не было).
  Future<DateTime?> lastSync(int regionId);

  /// Сохранить время последней синхронизации региона.
  Future<void> setLastSync(int regionId, DateTime time);

  /// Добавить операцию в оффлайн-очередь (push-очередь).
  Future<void> enqueueOutbox(OutboxEntry entry);

  /// Все ожидающие отправки операции в порядке очереди.
  Future<List<OutboxEntry>> pendingOutbox();

  /// Убрать выполненную операцию из очереди.
  Future<void> removeOutbox(int id);

  /// Закрыть хранилище.
  Future<void> close();
}