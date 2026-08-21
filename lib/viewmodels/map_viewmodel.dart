// lib/viewmodels/map_viewmodel.dart

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../exceptions/data_exception.dart';
import '../models/app_regions.dart';
import '../models/outbox_entry.dart';
import '../models/point_stats.dart';
import '../models/wifi_point.dart';
import '../services/point_store.dart';
import '../services/point_store_factory.dart';
import '../services/device_identity_service.dart';
import '../services/api_client.dart';

// ---------------------------------------------------------------------------
// Тип сортировки
// ---------------------------------------------------------------------------

enum SortType { nameTop, nameBottom, ratingTop, ratingBottom }

/// Близость пользователя к точке: подключён (connected),
/// рядом, но не подключён (nearby), или далеко (far).
enum PointProximity { connected, nearby, far }

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

class MapViewModel extends ChangeNotifier {
  MapViewModel({
    PointStore? store,
    DeviceIdentityService? deviceIdentityService,
    ApiClient? apiClient,
  }) {
    _store = store ?? createPointStore();
    _deviceIdentityService = deviceIdentityService ?? DeviceIdentityService();
    _apiClient = apiClient ?? ApiClient();
  }

  late final PointStore _store;
  late final DeviceIdentityService _deviceIdentityService;
  late final ApiClient _apiClient;

  /// Регион, с которым работает пользователь (по умолчанию Новосибирск, 54).
  int _selectedRegionId = 54;
  int get selectedRegionId => _selectedRegionId;

  void setSelectedRegionId(int regionId) {
    if (_selectedRegionId == regionId) return;
    _selectedRegionId = regionId;
    _applyFilterAndSort();
  }

  /// Роль пользователя (default / volunteer / admin). Определяет видимость
  /// слоёв [datasetType]: default → public, volunteer → + volunteer_test,
  /// admin → все слои.
  String _role = 'default';
  String get role => _role;

  /// Устанавливает роль из [AuthSession.role] и пересчитывает видимость слоёв.
  void setRole(String role) {
    if (_role == role) return;
    _role = role;
    _applyFilterAndSort();
  }

  bool _canSeeDataset(String datasetType) {
    switch (_role) {
      case 'volunteer':
        return datasetType == 'public' || datasetType == 'volunteer_test';
      case 'admin':
        return true;
      default:
        return datasetType == 'public';
    }
  }

  /// Список регионов для селектора. Стартует со встроенного справочника
  /// [kAppRegions] и обновляется с бэкенда ([ApiClient.fetchRegions]).
  List<AppRegion> _regions = kAppRegions;
  List<AppRegion> get regions => _regions;

  /// Кэшированный user_id для ролевой синхронизации (роль влияет на слои).
  String? _userId;

  Future<void> refreshRegions() async {
    try {
      final regions = await _apiClient.fetchRegions();
      if (regions.isEmpty) return;
      _regions = regions;
      notifyListeners();
    } catch (_) {
      // сервер недоступен — остаёмся на встроенном списке
    }
  }

  // Контроллер анимированной карты (инициализируется из StatefulWidget)
  late AnimatedMapController mapController;

  // ---- Данные ----------------------------------------------------------------
  List<WiFiPoint> _allPoints = []; // исходный список (без фильтра)
  List<WiFiPoint> _points = []; // отображаемый список

  List<WiFiPoint> get points => _points;

  // ---- Состояние -------------------------------------------------------------
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isFileLoaded = false;
  bool get isFileLoaded => _isFileLoaded;

  String? _lastError;
  String? get lastError => _lastError;

  // ---- Поиск -----------------------------------------------------------------
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  // ---- Сортировка ------------------------------------------------------------
  SortType _currentSort = SortType.ratingTop;
  SortType get currentSort => _currentSort;

  // ---- Геолокация ------------------------------------------------------------
  Position? _userPosition;
  Position? get userPosition => _userPosition;

  LatLng? get userLatLng => _userPosition == null
      ? null
      : LatLng(_userPosition!.latitude, _userPosition!.longitude);

  // ---- Высота шторки (для расчёта смещения камеры) --------------------------
  /// Значение от 0.0 до 1.0 — текущая доля экрана, занятая шторкой.
  double _sheetSize = 0.3;
  double get sheetSize => _sheetSize;

  void updateSheetSize(double size) {
    _sheetSize = size;
    // не вызываем notifyListeners — это не требует перерисовки
  }

  // ===========================================================================
  // Инициализация
  // ===========================================================================

  Future<void> init() async {
    await _loadFromStorage();
    await _fetchUserLocation();
    unawaited(refreshRegions());
  }

  Future<void> _loadFromStorage() async {
    _setLoading(true);
    try {
      final points = await _store.loadPoints();
      _allPoints = points;
      _applyFilterAndSort();
      if (points.isNotEmpty) _isFileLoaded = true;
    } on DataException catch (e) {
      _lastError = e.message;
    } catch (e) {
      _lastError = 'Не удалось загрузить данные: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addNetworkPoint({
    String password = '',
  }) async {
    await refreshUserLocation();

    if (_userPosition == null) {
      _lastError = 'Не удалось определить геопозицию.';
      notifyListeners();
      return false;
    }

    final wifi = WifiInfoWrapper();
    final ssid = await wifi.getWifiName();

    if (ssid == null || ssid.isEmpty) {
      _lastError = 'Вы не подключены к Wi-Fi.';
      notifyListeners();
      return false;
    }

    // Проверяем существование рядом
    for (final point in _allPoints) {
      final distance = Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        point.lat,
        point.lng,
      );

      if (distance < 30 && point.name == ssid) {
        _lastError = 'Такая точка уже существует рядом.';
        notifyListeners();
        return false;
      }
    }

    // Получаем или лениво генерируем стойкий идентификатор устройства ТОЛЬКО в момент добавления новой точки
    final identity = await _deviceIdentityService.getOrCreateDeviceIdentity();
    debugPrint('Идентификатор устройства (SHA-256 hex) для авторизации: ${identity.hexHash}');

    final point = WiFiPoint(
      id: const Uuid().v4(),
      name: ssid,
      password: password,
      rating: 0,
      lat: _userPosition!.latitude,
      lng: _userPosition!.longitude,
    );

    _allPoints.add(point);

    _applyFilterAndSort();

    // Локально точка добавлена. Пытаемся синхронизировать с бэкендом:
    // регистрируем устройство (только теперь) и создаём точку на сервере.
    // При отсутствии сети точка остаётся локально и попадает в push-очередь.
    try {
      final session = await _apiClient.registerDevice(identity.rawId);
      final created = await _apiClient.createPoint(
        userId: session.userId,
        ssid: point.name,
        password: point.password,
        lat: point.lat,
        lon: point.lng,
        datasetType: point.datasetType,
      );
      setRole(session.role);
      _userId = session.userId;

      // Заменяем локальную копию на серверную: у неё корректный region_id
      // (бэкенд определил регион через PostGIS).
      final serverPoint = created.toWiFiPoint();
      final index = _allPoints.indexWhere((p) => p.id == point.id);
      if (index >= 0) {
        _allPoints[index] = serverPoint;
      } else {
        _allPoints.add(serverPoint);
      }
      await _store.upsertPoint(serverPoint);
      _applyFilterAndSort();
    } catch (e) {
      await _store.enqueueOutbox(OutboxEntry(
        kind: OutboxEntry.kindPoint,
        payload: {
          'local_id': point.id,
          'ssid': point.name,
          'password': point.password,
          'lat': point.lat,
          'lon': point.lng,
          'dataset_type': point.datasetType,
        },
        createdAt: DateTime.now(),
      ));
      debugPrint('Сеть недоступна — точка добавлена в очередь отправки: $e');
    }

    await _store.savePoints(_allPoints);
    _lastError = null;

    notifyListeners();

    return true;
  }

  // ===========================================================================
  // Импорт / экспорт
  // ===========================================================================

  /// Открывает file_picker и загружает JSON.
  /// Возвращает [MapFiDataException] если файл повреждён — UI покажет ошибку.
  Future<void> pickAndLoadDatabase() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true, // нужны байты для Web/Mobile
    );
    if (result == null) return;

    final platformFile = result.files.single;
    final Uint8List? bytes = platformFile.bytes;
    if (bytes == null) {
      _lastError = 'Не удалось прочитать файл.';
      notifyListeners();
      return;
    }

    _setLoading(true);
    try {
      final points = _store.parseFromBytes(bytes);
      _allPoints = points;
      _applyFilterAndSort();
      await _store.savePoints(_allPoints);
      _isFileLoaded = true;
      _lastError = null;
    } on DataException catch (e) {
      _lastError = e.message;
    } finally {
      _setLoading(false);
    }
  }

  /// Экспортирует текущий список точек в файл через системный диалог.
  Future<void> exportDatabase() async {
    try {
      final dir = await getTemporaryDirectory();

      final file = File(
        '${dir.path}/mapfi_export.json',
      );

      final json = _allPoints.map((e) => e.toJson()).toList();

      await file.writeAsString(
        jsonEncode(json),
        flush: true,
      );

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Экспорт базы MapFi',
      );

      _lastError = null;
    } catch (e) {
      _lastError = 'Ошибка экспорта: $e';
    }

    notifyListeners();
  }

  // ===========================================================================
  // Серверная синхронизация
  // ===========================================================================

  /// Полная синхронизация региона: сначала отправка оффлайн-очереди,
  /// затем дельта-загрузка изменений с сервера.
  ///
  /// Возвращает количество обработанных записей; при недоступности сервера — null.
  Future<int?> synchronizeRegion(int regionId) async {
    _setLoading(true);
    try {
      final pushed = await pushPending();
      final pulled = await _pullFromServer(regionId: regionId);
      if (pulled == null) {
        // ошибка загрузки — сохраняем _lastError из _pullFromServer
        return null;
      }
      _lastError = null;
      return pushed + pulled;
    } finally {
      _setLoading(false);
    }
  }

  /// Отправка всех записей из оффлайн-очереди ([OutboxEntry]).
  ///
  /// При успешном создании точки локальная копия заменяется на серверную
  /// (чтобы при следующей загрузке не возникло дублей из-за серверного id).
  Future<int> pushPending() async {
    final entries = await _store.pendingOutbox();
    if (entries.isEmpty) return 0;

    final identity = await _deviceIdentityService.getOrCreateDeviceIdentity();
    final session = await _apiClient.registerDevice(identity.rawId);
    setRole(session.role);
    _userId = session.userId;

    var sent = 0;
    for (final entry in entries) {
      try {
        if (entry.kind == OutboxEntry.kindPoint) {
          final p = entry.payload;
          final created = await _apiClient.createPoint(
            userId: session.userId,
            ssid: p['ssid'] as String,
            password: (p['password'] as String?) ?? '',
            lat: (p['lat'] as num).toDouble(),
            lon: (p['lon'] as num).toDouble(),
            datasetType: (p['dataset_type'] as String?) ?? 'public',
          );

          final localId = p['local_id'] as String?;
          if (localId != null) {
            await _store.removePoint(localId);
          }
          await _store.upsertPoint(created.toWiFiPoint());
        } else if (entry.kind == OutboxEntry.kindFeedback) {
          await _apiClient.createFeedback(
            userId: session.userId,
            pointId: entry.payload['ap_id'] as String,
            regionId: (entry.payload['region_id'] as num).toInt(),
            type: entry.payload['type'] as String,
          );
        }
        await _store.removeOutbox(entry.id!);
        sent++;
      } on ApiException catch (e) {
        // Неисправимые ошибки (валидация/бан/нет точки) — дропаем запись.
        // Сетевые сбои оставляем в очереди и останавливаем цикл.
        final status = e.statusCode;
        if (status != null && status >= 400 && status < 500) {
          await _store.removeOutbox(entry.id!);
        } else {
          break;
        }
      } catch (_) {
        break;
      }
    }
    return sent;
  }

  /// Дельта-загрузка точек региона по watermark последней синхронизации.
  ///
  /// Применяет [updated_at]-смещения, удаляет локальные точки, помеченные
  /// на сервере `is_deleted`, и сохраняет новый watermark.
  /// Возвращает количество полученных изменений; при ошибке — null.
  Future<int?> _pullFromServer({required int regionId}) async {
    try {
      final since = await _store.lastSync(regionId);
      final sync = await _apiClient.syncPoints(
        regionId: regionId,
        since: since,
        userId: _userId,
      );

      final upserts = <WiFiPoint>[];
      final deletes = <String>[];
      for (final p in sync.points) {
        if (p.isDeleted) {
          deletes.add(p.id);
        } else {
          upserts.add(p.toWiFiPoint());
        }
      }

      await _store.upsertPoints(upserts);
      for (final id in deletes) {
        await _store.removePoint(id);
      }
      await _store.setLastSync(regionId, sync.serverTime);

      _allPoints = await _store.loadPoints();
      _applyFilterAndSort();
      if (_allPoints.isNotEmpty) _isFileLoaded = true;
      return sync.points.length;
    } on ApiException catch (e) {
      _lastError = 'Ошибка синхронизации с сервером: ${e.message}';
      return null;
    } catch (e) {
      _lastError = 'Сервер недоступен: $e';
      return null;
    }
  }

  // ===========================================================================
  // Поиск и сортировка
  // ===========================================================================

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilterAndSort();
  }

  void changeSort(SortType type) {
    _currentSort = type;
    _applyFilterAndSort();
  }

  void _applyFilterAndSort() {
    List<WiFiPoint> filtered = List.of(_allPoints)
        .where((p) =>
            _canSeeDataset(p.datasetType) &&
            (p.regionId == 0 || p.regionId == _selectedRegionId))
        .toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered =
          filtered.where((p) => p.name.toLowerCase().contains(q)).toList();
    }

    switch (_currentSort) {
      case SortType.nameTop:
        filtered.sort((a, b) => a.name.compareTo(b.name));
      case SortType.nameBottom:
        filtered.sort((a, b) => b.name.compareTo(a.name));
      case SortType.ratingTop:
        filtered.sort((a, b) => b.rating.compareTo(a.rating));
      case SortType.ratingBottom:
        filtered.sort((a, b) => a.rating.compareTo(b.rating));
    }

    _points = filtered;
    notifyListeners();
  }

  // ===========================================================================
  // Геолокация
  // ===========================================================================

  Future<void> _fetchUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      _userPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    } catch (_) {
      // Геолокация недоступна — приложение работает без неё
    }
  }

  Future<void> refreshUserLocation() => _fetchUserLocation();

  // ===========================================================================
  // Рейтинг / верификация
  // ===========================================================================

  /// Определяет близость пользователя к точке:
/// - [PointProximity.connected] — подключён к этой сети (SSID совпал,
///   находимся в радиусе 50 м);
/// - [PointProximity.nearby] — рядом, но не подключён;
/// - [PointProximity.far] — далеко (или геолокация недоступна).
  Future<PointProximity> proximityOf(WiFiPoint point) async {
    if (_userPosition == null) return PointProximity.far;

    final distanceMeters = Geolocator.distanceBetween(
      _userPosition!.latitude,
      _userPosition!.longitude,
      point.lat,
      point.lng,
    );

    if (distanceMeters > 50) return PointProximity.far;

    // Проверяем SSID через wifi_info_flutter
    try {
      final info = WifiInfoWrapper();
      final ssid = await info.getWifiName();
      if (ssid == null) return PointProximity.nearby;
      final cleanSsid = ssid.replaceAll('"', '');
      if (cleanSsid == point.name) return PointProximity.connected;
    } catch (_) {
      return PointProximity.nearby;
    }
    return PointProximity.nearby;
  }

  /// Верифицирует точку: возвращает true если пользователь подключён к сети
  /// точки (см. [proximityOf]). При успехе отправляет на бэкенд отзыв
  /// типа [FeedbackTypes.verify] (в оффлайне — в push-очередь).
  Future<bool> verifyPoint(WiFiPoint point) async {
    final proximity = await proximityOf(point);
    if (proximity != PointProximity.connected) return false;

    await submitFeedback(point, FeedbackTypes.verify);
    return true;
  }

  /// Загружает агрегированные отзывы по точке за период [days].
  /// При недоступности сервера возвращает пустую статистику.
  Future<PointStats> loadPointStats(WiFiPoint point, {int days = 30}) async {
    try {
      return await _apiClient.fetchPointStats(
        pointId: point.id,
        regionId: point.regionId,
        days: days,
      );
    } catch (_) {
      return PointStats.empty;
    }
  }

  /// Гарантирует наличие стойкого идентификатора устройства и возвращает
  /// его rawId (Widevine hex на Android, UUID на прочих платформах).
  /// Используется в Drawer для отображения токена (копирование/разбан в БД).
  Future<String> getOrCreateDeviceToken() async {
    final identity = await _deviceIdentityService.getOrCreateDeviceIdentity();
    return identity.rawId;
  }

  /// Отправляет отзыв по точке на бэкенд.
  ///
  /// При недоступности сервера (сетевой сбой/5xx) отзыв попадает в
  /// push-очередь [OutboxEntry.kindFeedback]; ошибки валидации (4xx, например
  /// несуществующая точка) отбрасываются.
  Future<void> submitFeedback(WiFiPoint point, String type) async {
    try {
      final identity = await _deviceIdentityService.getOrCreateDeviceIdentity();
      final session = await _apiClient.registerDevice(identity.rawId);
      setRole(session.role);
      _userId = session.userId;
      await _apiClient.createFeedback(
        userId: session.userId,
        pointId: point.id,
        regionId: point.regionId,
        type: type,
      );
    } on ApiException catch (e) {
      final status = e.statusCode;
      if (status == null || status < 400 || status >= 500) {
        await _enqueueFeedback(point, type);
      }
    } catch (_) {
      await _enqueueFeedback(point, type);
    }
  }

  Future<void> _enqueueFeedback(WiFiPoint point, String type) =>
      _store.enqueueOutbox(OutboxEntry(
        kind: OutboxEntry.kindFeedback,
        payload: {
          'ap_id': point.id,
          'region_id': point.regionId,
          'type': type,
        },
        createdAt: DateTime.now(),
      ));

  // ===========================================================================
  // Фокус камеры с вертикальным смещением (исправление Ошибки 2)
  // ===========================================================================

  /// Анимирует камеру к [point] со смещением, чтобы маркер не оказался
  /// за нижней шторкой.
  ///
  /// [screenHeight] — полная высота экрана в логических пикселях.
  ///
  /// Алгоритм:
  ///   1. Вычисляем высоту видимой области над шторкой.
  ///   2. Центр видимой области находится выше геометрического центра экрана.
  ///   3. Смещаем целевую точку «вниз» (уменьшаем широту), чтобы камера
  ///      центрировалась ниже маркера, а маркер оказывался в верхней части
  ///      видимой области.
  void focusOnPoint(WiFiPoint point, double screenHeight, double zoom) {
    try {
      final sheetPixelHeight = screenHeight * _sheetSize;
      //final visibleHeight = screenHeight - sheetPixelHeight;

      // Смещение от центра экрана до центра видимой области (в пикселях):
      //   centreOffset = sheetPixelHeight / 2
      // Нам нужно сдвинуть камеру так, чтобы маркер попал в центр видимой области.
      // Камера должна смотреть на точку, сдвинутую «вниз» на centreOffset пикселей.
      final offsetPixels = sheetPixelHeight / 2;

      // Градусов широты на пиксель при текущем зуме:
      //   metersPerPixel = 156543.03392 * cos(lat) / 2^zoom
      //   degreesPerPixel = metersPerPixel / 111320
      final latRad = point.lat * math.pi / 180.0;
      final metersPerPixel =
          156543.03392 * math.cos(latRad) / math.pow(2, zoom);
      final degreesLatPerPixel = metersPerPixel / 111320.0;

      // Сдвигаем целевую координату вниз по широте (уменьшаем lat):
      final adjustedLat = point.lat - degreesLatPerPixel * offsetPixels;

      mapController.animateTo(
        dest: LatLng(adjustedLat, point.lng),
        zoom: zoom,
      );
    } catch (e) {
      debugPrint("Карте не инициализированна для анимации: $e");
    }
  }

  // ===========================================================================
  // Вспомогательное
  // ===========================================================================

  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Обёртка для wifi_info_flutter (изолирует платформо-зависимый код)
// ---------------------------------------------------------------------------

class WifiInfoWrapper {
  Future<String?> getWifiName() async {
    try {
      final info = NetworkInfo();
      final ssid = await info.getWifiName();
      if (ssid == null || ssid.isEmpty) return null;
      // Убираем кавычки, если есть
      return ssid.replaceAll('"', '');
    } catch (_) {
      return null;
    }
  }
}

// ignore: deprecated_member_use
class WifiInfo {
  Future<String?> getWifiName() => Future.value(null); // заглушка
}
