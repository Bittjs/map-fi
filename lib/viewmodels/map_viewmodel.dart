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
import '../models/wifi_point.dart';
import '../services/repository_service.dart';
import '../services/sync_service.dart';

// ---------------------------------------------------------------------------
// Тип сортировки
// ---------------------------------------------------------------------------

enum SortType { nameTop, nameBottom, ratingTop, ratingBottom }

// ---------------------------------------------------------------------------
// ViewModel
// ---------------------------------------------------------------------------

class MapViewModel extends ChangeNotifier {
  MapViewModel() {
    _repository = WiFiRepository();
    _syncService = SyncService(_repository);
  }

  late final WiFiRepository _repository;
  late final SyncService _syncService;

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
  }

  Future<void> _loadFromStorage() async {
    _setLoading(true);
    try {
      final points = await _repository.loadPoints();
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

    await _repository.savePoints(_allPoints);

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
      final points = _repository.parseFromBytes(bytes);
      _allPoints = points;
      _applyFilterAndSort();
      await _repository.savePoints(_allPoints);
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
  // GitHub синхронизация
  // ===========================================================================

  SyncService get syncService => _syncService;

  Future<SyncResult> synchronize() async {
    _setLoading(true);
    try {
      return await _syncService.synchronize();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> applySyncResult(SyncResult result) async {
    if (result.status != SyncStatus.newDataAvailable) return;
    _allPoints = result.points;
    _applyFilterAndSort();
    await _repository.savePoints(_allPoints);
    _isFileLoaded = true;
    _lastError = null;
    notifyListeners();
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
    List<WiFiPoint> filtered = _allPoints;

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

  /// Проверяет точку: возвращает true если текущий SSID совпадает с именем
  /// точки И пользователь находится в радиусе 50 метров.
  Future<bool> verifyPoint(WiFiPoint point) async {
    if (_userPosition == null) return false;

    final distanceMeters = Geolocator.distanceBetween(
      _userPosition!.latitude,
      _userPosition!.longitude,
      point.lat,
      point.lng,
    );

    if (distanceMeters > 50) return false;

    // Проверяем SSID через wifi_info_flutter
    // (плагин требует android.permission.ACCESS_FINE_LOCATION)
    try {
      // Импортируем динамически чтобы не ломать компиляцию на платформах
      // без поддержки wifi_info
      final info = WifiInfoWrapper();
      final ssid = await info.getWifiName();
      if (ssid == null) return false;
      final cleanSsid = ssid.replaceAll('"', '');
      return cleanSsid == point.name;
    } catch (_) {
      return false;
    }
  }

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
