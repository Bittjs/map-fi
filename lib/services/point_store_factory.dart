// lib/services/point_store_factory.dart
// Фабрика локального хранилища с условным импортом по платформе.

import 'point_store.dart';
import 'point_store_stub.dart'
    if (dart.library.io) 'point_store_io.dart' as impl;

/// Создаёт локальное хранилище для текущей платформы:
/// - io (Android/iOS/Desktop) → SQLite
/// - web → in-memory (приложение веб — режим просмотра)
PointStore createPointStore() => impl.createPointStore();