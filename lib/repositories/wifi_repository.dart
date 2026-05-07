// lib/repositories/wifi_repository.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../exceptions/mapfi_data_exception.dart';
import '../models/wifi_point.dart';

/// Репозиторий для хранения точек Wi-Fi в локальном файле points.json.
/// Все публичные методы выбрасывают [MapFiDataException] при ошибке данных.
class WiFiRepository {
  static const _fileName = 'points.json';

  // ---------------------------------------------------------------------------
  // Путь к файлу
  // ---------------------------------------------------------------------------

  Future<File> get _localFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  // ---------------------------------------------------------------------------
  // Чтение
  // ---------------------------------------------------------------------------

  /// Загружает точки из основного локального файла.
  /// Возвращает пустой список, если файл не существует.
  Future<List<WiFiPoint>> loadPoints() async {
    final file = await _localFile;
    if (!file.existsSync()) return [];
    final bytes = await file.readAsBytes();
    return _parseBytes(bytes);
  }

  /// Парсит точки из сырых байтов (для импорта через file_picker).
  List<WiFiPoint> parseFromBytes(Uint8List bytes) => _parseBytes(bytes);

  // ---------------------------------------------------------------------------
  // Запись
  // ---------------------------------------------------------------------------

  /// Сохраняет список точек в основной файл.
  Future<void> savePoints(List<WiFiPoint> points) async {
    final file = await _localFile;
    final data = jsonEncode(points.map((p) => p.toJson()).toList());
    await file.writeAsString(data, flush: true);
  }

  // ---------------------------------------------------------------------------
  // Внутренний парсинг
  // ---------------------------------------------------------------------------

  List<WiFiPoint> _parseBytes(Uint8List bytes) {
    late final dynamic decoded;
    try {
      final raw = utf8.decode(bytes);
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const MapFiDataException(
        'Ошибка формата файла. Проверьте структуру JSON.',
      );
    }

    if (decoded is! List) {
      throw const MapFiDataException(
        'Ошибка формата файла. Проверьте структуру JSON: '
        'корневой элемент должен быть массивом.',
      );
    }

    final points = <WiFiPoint>[];
    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i];
      if (item is! Map<String, dynamic>) {
        throw MapFiDataException(
          'Ошибка формата файла. Проверьте структуру JSON: '
          'элемент #$i не является объектом.',
        );
      }
      // WiFiPoint.fromJson сам бросит MapFiDataException при недостающих полях
      points.add(WiFiPoint.fromJson(item));
    }
    return points;
  }
}
