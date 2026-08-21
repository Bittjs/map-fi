// test/api_client_integration_test.dart
// Интеграционный тест: взаимодействие Flutter-клиента с живым бэкендом.
// Требует запущенный сервер (server/main.go) на localhost:23125.
// Если сервер недоступен — тест пропускается.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mapfi/models/api_models.dart';
import 'package:mapfi/services/api_client.dart';
import 'package:uuid/uuid.dart';

const _baseUrl = 'http://localhost:23125';

Future<bool> _isServerUp() async {
  try {
    final socket = await Socket.connect('localhost', 23125,
        timeout: const Duration(seconds: 3));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  final client = ApiClient(baseUrl: _baseUrl);

  setUpAll(() async {
    final up = await _isServerUp();
    if (!up) {
      markTestSkipped('Бэкенд недоступен на $_baseUrl — тест пропущен.');
    }
  });

  test('регистрация устройства → создание точки → синхронизация', () async {
    final deviceToken = const Uuid().v4();

    // 1. Авторизация устройства
    final session = await client.registerDevice(deviceToken);
    expect(session.userId, isNotEmpty);
    expect(session.role, 'default');

    // 2. Создание точки (координаты Москвы → region_id 77)
    final point = await client.createPoint(
      userId: session.userId,
      ssid: 'MapFi-Integration-Test',
      password: 'secret',
      lat: 55.7558,
      lon: 37.6173,
    );
    expect(point.id, isNotEmpty);
    expect(point.regionId, 77);
    expect(point.ssid, 'MapFi-Integration-Test');

    // 2b. Конвертация в локальную модель сохраняет регион и слой
    final local = point.toWiFiPoint();
    expect(local.regionId, 77);
    expect(local.datasetType, 'public');
    expect(local.name, 'MapFi-Integration-Test');

    // 3. Синхронизация региона — точка должна быть в ответе
    final sync = await client.syncPoints(regionId: 77);
    expect(sync.points.any((p) => p.id == point.id), isTrue,
        reason: 'Созданная точка должна попасть в синхронизацию');

    // 4. Отзыв по точке
    await client.createFeedback(
      userId: session.userId,
      pointId: point.id,
      regionId: point.regionId,
      type: 'verify',
    );
  });

  test('повторная регистрация того же токена → тот же user_id', () async {
    final deviceToken = const Uuid().v4();

    final first = await client.registerDevice(deviceToken);
    final second = await client.registerDevice(deviceToken);

    expect(second.userId, first.userId,
        reason: 'Один и тот же device_token должен давать одного пользователя');
  });

  test('ошибка валидации: создание точки без координат', () async {
    try {
      await client.createPoint(
        userId: const Uuid().v4(),
        ssid: 'NoCoords',
        lat: 0,
        lon: 0,
      );
      fail('Ожидали ApiException из-за нулевых координат');
    } on ApiException catch (e) {
      expect(e.statusCode, 400);
    }
  });

  test('ServerSync корректно десериализуется', () async {
    final sync = await client.syncPoints(regionId: 77);
    expect(sync.serverTime, isA<DateTime>());
    expect(sync.points, isA<List<ApiPoint>>());
  });

  test('GET /api/v1/regions возвращает список регионов', () async {
    final regions = await client.fetchRegions();
    expect(regions, isNotEmpty);
    expect(regions.map((r) => r.id), containsAll([54, 77]));
    expect(regions.first.name, isNotEmpty);
  });
}