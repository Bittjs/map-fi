// test/feedback_stats_test.dart
// Тесты текущей партии: статистика по точке (PointStats, fetchPointStats,
// loadPointStats), близость/верификация (proximityOf, verifyPoint),
// токен устройства в Drawer (getOrCreateDeviceToken) и настройки сервера.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mapfi/models/point_stats.dart';
import 'package:mapfi/models/wifi_point.dart';
import 'package:mapfi/services/api_client.dart';
import 'package:mapfi/services/device_identity_service.dart';
import 'package:mapfi/services/server_settings.dart';
import 'package:mapfi/viewmodels/map_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_point_store.dart';

const _json = {'content-type': 'application/json'};

const _point = WiFiPoint(
  id: 'p1',
  name: 'Net',
  password: '',
  rating: 0,
  lat: 55.0,
  lng: 83.0,
  regionId: 54,
);

MapViewModel _makeVm({
  required FakePointStore store,
  required MockClient client,
}) =>
    MapViewModel(
      store: store,
      deviceIdentityService: DeviceIdentityService(),
      apiClient: ApiClient(baseUrl: 'http://test', httpClient: client),
    );

MockClient _statsBackend(Map<String, dynamic> stats) =>
    MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/points/p1/stats') {
        return http.Response(jsonEncode(stats), 200, headers: _json);
      }
      return http.Response('not found', 404);
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('PointStats', () {
    test('fromJson считает проверки и жалобы', () {
      final stats = PointStats.fromJson({
        'point_id': 'p1',
        'region_id': 54,
        'days': 30,
        'counts': {'verify': 5, 'wrong_password': 1, 'other': 2},
      });

      expect(stats.pointId, 'p1');
      expect(stats.regionId, 54);
      expect(stats.days, 30);
      expect(stats.checks, 5);
      expect(stats.complaints, 3, reason: 'все типы, кроме verify');
    });

    test('likelyUnavailable при двух и более жалобах «точки нет/фейк»', () {
      final ok = PointStats.fromJson({
        'point_id': 'p1',
        'region_id': 54,
        'days': 30,
        'counts': {'point_not_found': 1, 'spam_fake': 1},
      });
      final borderline = PointStats.fromJson({
        'point_id': 'p1',
        'region_id': 54,
        'days': 30,
        'counts': {'point_not_found': 1},
      });
      final unrelated = PointStats.fromJson({
        'point_id': 'p1',
        'region_id': 54,
        'days': 30,
        'counts': {'wrong_password': 3},
      });

      expect(ok.likelyUnavailable, isTrue);
      expect(borderline.likelyUnavailable, isFalse);
      expect(unrelated.likelyUnavailable, isFalse);
    });

    test('empty не считается недоступной', () {
      expect(PointStats.empty.checks, 0);
      expect(PointStats.empty.complaints, 0);
      expect(PointStats.empty.likelyUnavailable, isFalse);
    });
  });

  group('fetchPointStats / loadPointStats', () {
    test('ApiClient.fetchPointStats шлёт region_id и days и парсит ответ', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/points/p1/stats');
        expect(request.url.queryParameters['region_id'], '54');
        expect(request.url.queryParameters['days'], '7');
        return http.Response(
            jsonEncode({
              'point_id': 'p1',
              'region_id': 54,
              'days': 7,
              'counts': {'verify': 2, 'point_not_found': 1},
            }),
            200,
            headers: _json);
      });
      final api = ApiClient(baseUrl: 'http://test', httpClient: client);

      final stats = await api.fetchPointStats(pointId: 'p1', regionId: 54, days: 7);

      expect(stats.checks, 2);
      expect(stats.complaints, 1);
      expect(stats.likelyUnavailable, isFalse);
    });

    test('loadPointStats возвращает статистику при рабочем сервере', () async {
      final vm = _makeVm(
        store: FakePointStore(),
        client: _statsBackend({
          'point_id': 'p1',
          'region_id': 54,
          'days': 30,
          'counts': {'verify': 5, 'wrong_password': 2},
        }),
      );

      final stats = await vm.loadPointStats(_point);

      expect(stats.checks, 5);
      expect(stats.complaints, 2);
    });

    test('loadPointStats при ошибке сервера возвращает пустую статистику', () async {
      final client =
          MockClient((request) async => http.Response('boom', 500));
      final vm = _makeVm(store: FakePointStore(), client: client);

      final stats = await vm.loadPointStats(_point);

      expect(stats, same(PointStats.empty));
    });
  });

  group('proximityOf / verifyPoint', () {
    test('proximityOf возвращает far без геопозиции', () async {
      final vm = _makeVm(store: FakePointStore(), client: _statsBackend({}));
      expect(await vm.proximityOf(_point), PointProximity.far);
    });

    test('verifyPoint отклоняет точку, к которой не подключён', () async {
      final store = FakePointStore();
      final vm = _makeVm(store: store, client: _statsBackend({}));

      final ok = await vm.verifyPoint(_point);

      expect(ok, isFalse);
      expect(await store.pendingOutbox(), isEmpty,
          reason: 'отзыв не отправляется, если пользователь не подключён');
    });
  });

  group('Токен устройства', () {
    test('getOrCreateDeviceToken возвращает стабильный rawId', () async {
      final vm = _makeVm(store: FakePointStore(), client: _statsBackend({}));

      final first = await vm.getOrCreateDeviceToken();
      final second = await vm.getOrCreateDeviceToken();

      expect(first, isNotEmpty);
      expect(second, first, reason: 'токен сохраняется между вызовами');
    });
  });

  group('ServerSettings', () {
    test('save нормализует URL и сохраняет в SharedPreferences', () async {
      await ServerSettings.save(' 192.168.0.5:23125/ ');

      expect(ServerSettings.baseUrl, 'http://192.168.0.5:23125');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('server_base_url'), 'http://192.168.0.5:23125');
    });

    test('save сохраняет https-схему', () async {
      await ServerSettings.save('https://api.example.com/');
      expect(ServerSettings.baseUrl, 'https://api.example.com');
    });

    test('load подхватывает сохранённый адрес', () async {
      SharedPreferences.setMockInitialValues({
        'server_base_url': 'http://10.0.2.2:23125',
      });

      await ServerSettings.load();

      expect(ServerSettings.baseUrl, 'http://10.0.2.2:23125');
    });

    test('load без сохранённого значения оставляет текущий адрес', () async {
      await ServerSettings.save('http://reset.test');
      SharedPreferences.setMockInitialValues({});

      await ServerSettings.load();

      expect(ServerSettings.baseUrl, 'http://reset.test');
    });
  });
}