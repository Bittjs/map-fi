// test/map_viewmodel_sync_test.dart

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mapfi/models/outbox_entry.dart';
import 'package:mapfi/models/wifi_point.dart';
import 'package:mapfi/services/api_client.dart';
import 'package:mapfi/services/device_identity_service.dart';
import 'package:mapfi/viewmodels/map_viewmodel.dart';

import 'fakes/fake_point_store.dart';

const _json = {'content-type': 'application/json'};

Map<String, dynamic> _pointJson({
  String id = 'p1',
  String ssid = 'Net',
  int regionId = 54,
}) =>
    {
      'id': id,
      'region_id': regionId,
      'ssid': ssid,
      'dataset_type': 'public',
      'lat': 55.0,
      'lon': 83.0,
      'is_deleted': false,
      'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
    };

MockClient _backend({
  List<Map<String, dynamic>> syncPoints = const [],
  int createPointStatus = 201,
  int feedbackStatus = 201,
}) {
  return MockClient((request) async {
    final path = request.url.path;

    if (request.method == 'POST' && path == '/api/v1/auth/device') {
      return http.Response(
          jsonEncode({'user_id': 'user-1', 'role': 'default'}), 200,
          headers: _json);
    }

    if (request.method == 'POST' && path == '/api/v1/points') {
      if (createPointStatus != 201) {
        return http.Response('{"error":"boom"}', createPointStatus,
            headers: _json);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode(_pointJson(id: 'server-${body['ssid']}')), 201,
          headers: _json);
    }

    if (request.method == 'POST' && path == '/api/v1/feedbacks') {
      if (feedbackStatus != 201) {
        return http.Response('{"error":"boom"}', feedbackStatus,
            headers: _json);
      }
      return http.Response(
          jsonEncode({'id': 'f1', 'status': 'accepted'}), 201,
          headers: _json);
    }

    if (request.method == 'GET' && path == '/api/v1/sync') {
      return http.Response(
          jsonEncode({
            'server_time': DateTime.utc(2026, 1, 2).toIso8601String(),
            'points': syncPoints,
          }),
          200,
          headers: _json);
    }

    return http.Response('not found', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  MapViewModel makeVm({
    required FakePointStore store,
    required MockClient client,
  }) =>
      MapViewModel(
        store: store,
        deviceIdentityService: DeviceIdentityService(),
        apiClient: ApiClient(baseUrl: 'http://test', httpClient: client),
      );

  test('synchronizeRegion тянет точки региона и сохраняет watermark', () async {
    final store = FakePointStore();
    final vm = makeVm(
      store: store,
      client: _backend(syncPoints: [_pointJson()]),
    );

    expect(await store.lastSync(54), isNull);

    final count = await vm.synchronizeRegion(54);

    expect(count, 1);
    expect(await store.lastSync(54), isNotNull);
    expect(store.points, hasLength(1));
    expect(store.points.single.id, 'p1');
  });

  test('synchronizeRegion повторно шлёт since (дельта-синк)', () async {
    final seenSinces = <String?>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path == '/api/v1/auth/device') {
        return http.Response(
            jsonEncode({'user_id': 'user-1', 'role': 'default'}), 200,
            headers: _json);
      }
      if (request.method == 'GET' && path == '/api/v1/sync') {
        seenSinces.add(request.url.queryParameters['since']);
        return http.Response(
            jsonEncode({
              'server_time': DateTime.utc(2026, 1, 2).toIso8601String(),
              'points': <Map<String, dynamic>>[],
            }),
            200,
            headers: _json);
      }
      return http.Response('not found', 404);
    });

    final store = FakePointStore();
    final vm = makeVm(store: store, client: client);

    await vm.synchronizeRegion(54);
    await vm.synchronizeRegion(54);

    expect(seenSinces.length, 2);
    expect(seenSinces.first, isNull, reason: 'первый раз — без since');
    expect(seenSinces.last, isNotNull, reason: 'второй раз — since из watermark');
  });

  test('удалённые на сервере точки убираются локально', () async {
    final store = FakePointStore();
    await store.upsertPoint(const WiFiPoint(
      id: 'gone',
      name: 'Old',
      password: '',
      rating: 0,
      lat: 55.0,
      lng: 83.0,
    ));

    final vm = makeVm(
      store: store,
      client: _backend(syncPoints: [
        {..._pointJson(id: 'gone'), 'is_deleted': true},
        _pointJson(id: 'live'),
      ]),
    );

    await vm.synchronizeRegion(54);

    expect(store.points.any((p) => p.id == 'gone'), isFalse);
    expect(store.points.any((p) => p.id == 'live'), isTrue);
  });

  test('pushPending отправляет оффлайн-точку и заменяет её серверной', () async {
    final store = FakePointStore();
    await store.upsertPoint(const WiFiPoint(
      id: 'L1',
      name: 'Net',
      password: '',
      rating: 0,
      lat: 55.0,
      lng: 83.0,
    ));
    await store.enqueueOutbox(OutboxEntry(
      kind: OutboxEntry.kindPoint,
      payload: {
        'local_id': 'L1',
        'ssid': 'Net',
        'password': '',
        'lat': 55.0,
        'lon': 83.0,
        'dataset_type': 'public',
      },
      createdAt: DateTime.utc(2026, 1, 1),
    ));

    final vm = makeVm(store: store, client: _backend());

    final sent = await vm.pushPending();

    expect(sent, 1);
    expect(await store.pendingOutbox(), isEmpty);
    expect(store.points.any((p) => p.id == 'server-Net'), isTrue,
        reason: 'локальная точка заменена на серверную с серверным id');
    expect(store.points.any((p) => p.id == 'L1'), isFalse);
  });

  test('pushPending оставляет запись в очереди при серверной ошибке 5xx', () async {
    final store = FakePointStore();
    await store.enqueueOutbox(OutboxEntry(
      kind: OutboxEntry.kindPoint,
      payload: {
        'local_id': 'L1',
        'ssid': 'Net',
        'password': '',
        'lat': 55.0,
        'lon': 83.0,
        'dataset_type': 'public',
      },
      createdAt: DateTime.utc(2026, 1, 1),
    ));

    final vm = makeVm(
      store: store,
      client: _backend(createPointStatus: 500),
    );

    final sent = await vm.pushPending();

    expect(sent, 0);
    expect(await store.pendingOutbox(), hasLength(1),
        reason: 'сетевую/серверную ошибку оставляем в очереди');
  });

  test('pushPending дропает запись при ошибке валидации 4xx', () async {
    final store = FakePointStore();
    await store.enqueueOutbox(OutboxEntry(
      kind: OutboxEntry.kindPoint,
      payload: {
        'local_id': 'L1',
        'ssid': 'Net',
        'password': '',
        'lat': 55.0,
        'lon': 83.0,
        'dataset_type': 'public',
      },
      createdAt: DateTime.utc(2026, 1, 1),
    ));

    final vm = makeVm(
      store: store,
      client: _backend(createPointStatus: 400),
    );

    final sent = await vm.pushPending();

    expect(sent, 0);
    expect(await store.pendingOutbox(), isEmpty,
        reason: 'неисправимую ошибку дропаем из очереди');
  });

  test('отображаются только точки выбранного региона (+ неизвестный регион 0)',
      () async {
    final store = FakePointStore();
    await store.upsertPoint(const WiFiPoint(
        id: 'novosibirsk', name: 'A', password: '', rating: 0, lat: 55.0, lng: 83.0, regionId: 54));
    await store.upsertPoint(const WiFiPoint(
        id: 'moscow', name: 'B', password: '', rating: 0, lat: 55.0, lng: 83.0, regionId: 77));
    await store.upsertPoint(const WiFiPoint(
        id: 'unknown', name: 'C', password: '', rating: 0, lat: 55.0, lng: 83.0, regionId: 0));

    final vm = makeVm(store: store, client: _backend());
    await vm.init();

    expect(vm.points.map((p) => p.id), containsAll(['novosibirsk', 'unknown']));
    expect(vm.points.map((p) => p.id), isNot(contains('moscow')));

    vm.setSelectedRegionId(77);
    expect(vm.points.map((p) => p.id), containsAll(['moscow', 'unknown']));
    expect(vm.points.map((p) => p.id), isNot(contains('novosibirsk')));
  });

  test('слои dataset_type зависят от роли пользователя', () async {
    WiFiPoint p(String id, String dataset) => WiFiPoint(
        id: id,
        name: id,
        password: '',
        rating: 0,
        lat: 55.0,
        lng: 83.0,
        regionId: 54,
        datasetType: dataset);

    final store = FakePointStore();
    await store.upsertPoint(p('pub', 'public'));
    await store.upsertPoint(p('vt', 'volunteer_test'));
    await store.upsertPoint(p('dt', 'dev_test'));

    final vm = makeVm(store: store, client: _backend());
    await vm.init();

    // default — только public
    expect(vm.points.map((p) => p.id), ['pub']);

    vm.setRole('volunteer');
    expect(vm.points.map((p) => p.id), containsAll(['pub', 'vt']));
    expect(vm.points.map((p) => p.id), isNot(contains('dt')));

    vm.setRole('admin');
    expect(vm.points.map((p) => p.id), containsAll(['pub', 'vt', 'dt']));
  });

  test('submitFeedback отправляет отзыв на сервер', () async {
    final store = FakePointStore();
    final feedbackBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path == '/api/v1/auth/device') {
        return http.Response(
            jsonEncode({'user_id': 'user-1', 'role': 'default'}), 200,
            headers: _json);
      }
      if (request.method == 'POST' && path == '/api/v1/feedbacks') {
        feedbackBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        expect(request.headers['X-User-ID'], 'user-1');
        return http.Response(
            jsonEncode({'id': 'f1', 'status': 'accepted'}), 201,
            headers: _json);
      }
      return http.Response('not found', 404);
    });
    final vm = makeVm(store: store, client: client);

    const point = WiFiPoint(
        id: 'p1', name: 'Net', password: '', rating: 0, lat: 55.0, lng: 83.0, regionId: 54);
    await vm.submitFeedback(point, 'verify');

    expect(feedbackBodies, hasLength(1));
    expect(feedbackBodies.single, {'ap_id': 'p1', 'region_id': 54, 'type': 'verify'});
    expect(await store.pendingOutbox(), isEmpty);
  });

  test('submitFeedback при сетевой/серверной ошибке кладёт отзыв в очередь',
      () async {
    final store = FakePointStore();
    final vm = makeVm(store: store, client: _backend(feedbackStatus: 500));

    const point = WiFiPoint(
        id: 'p1', name: 'Net', password: '', rating: 0, lat: 55.0, lng: 83.0, regionId: 54);
    await vm.submitFeedback(point, 'verify');

    final pending = await store.pendingOutbox();
    expect(pending, hasLength(1));
    expect(pending.single.kind, OutboxEntry.kindFeedback);
    expect(pending.single.payload['type'], 'verify');
  });

  test('submitFeedback при 4xx отбрасывает отзыв', () async {
    final store = FakePointStore();
    final vm = makeVm(store: store, client: _backend(feedbackStatus: 400));

    const point = WiFiPoint(
        id: 'p1', name: 'Net', password: '', rating: 0, lat: 55.0, lng: 83.0, regionId: 54);
    await vm.submitFeedback(point, 'verify');

    expect(await store.pendingOutbox(), isEmpty);
  });

  test('refreshRegions обновляет список регионов с бэкенда', () async {
    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/api/v1/regions') {
        return http.Response(
            jsonEncode({
              'regions': [
                {'id': 54, 'name': 'Новосибирская область'},
                {'id': 77, 'name': 'Москва'},
                {'id': 78, 'name': 'Санкт-Петербург'},
              ]
            }),
            200,
            headers: _json);
      }
      return http.Response('not found', 404);
    });

    final vm = makeVm(store: FakePointStore(), client: client);

    expect(vm.regions, hasLength(2), reason: 'стартуем со встроенного списка');

    await vm.refreshRegions();

    expect(vm.regions, hasLength(3));
    expect(vm.regions.map((r) => r.id), contains(78));
  });

  test('refreshRegions при недоступном сервере сохраняет fallback', () async {
    final client = MockClient((request) async => http.Response('boom', 500));
    final vm = makeVm(store: FakePointStore(), client: client);

    await vm.refreshRegions();

    expect(vm.regions, hasLength(2));
  });

  test('synchronizeRegion шлёт X-User-ID после регистрации', () async {
    final syncUserIds = <String?>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path == '/api/v1/auth/device') {
        return http.Response(
            jsonEncode({'user_id': 'user-1', 'role': 'volunteer'}), 200,
            headers: _json);
      }
      if (request.method == 'POST' && path == '/api/v1/points') {
        return http.Response(
            jsonEncode(_pointJson(id: 'server-Net')), 201,
            headers: _json);
      }
      if (request.method == 'GET' && path == '/api/v1/sync') {
        syncUserIds.add(request.headers['X-User-ID']);
        return http.Response(
            jsonEncode({
              'server_time': DateTime.utc(2026, 1, 2).toIso8601String(),
              'points': <Map<String, dynamic>>[],
            }),
            200,
            headers: _json);
      }
      return http.Response('not found', 404);
    });

    final store = FakePointStore();
    await store.enqueueOutbox(OutboxEntry(
      kind: OutboxEntry.kindPoint,
      payload: {
        'local_id': 'L1',
        'ssid': 'Net',
        'password': '',
        'lat': 55.0,
        'lon': 83.0,
        'dataset_type': 'public',
      },
      createdAt: DateTime.utc(2026, 1, 1),
    ));

    final vm = makeVm(store: store, client: client);
    await vm.synchronizeRegion(54);

    expect(syncUserIds, isNotEmpty);
    expect(syncUserIds.last, 'user-1',
        reason: 'после регистрации ролевой фильтр передаётся через X-User-ID');
    expect(vm.role, 'volunteer');
  });
}