// lib/services/json_point_parser.dart
// Парсинг точек из JSON-байтов (импорт файлов).

import 'dart:convert';
import 'dart:typed_data';

import '../exceptions/data_exception.dart';
import '../models/wifi_point.dart';

class JsonPointParser {
  /// Парсит список точек из сырых байтов.
  ///
  /// Ожидается JSON-массив объектов с полями WiFiPoint.
  static List<WiFiPoint> parsePoints(Uint8List bytes) {
    late final dynamic decoded;
    try {
      final raw = utf8.decode(bytes);
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const DataException(
        'Ошибка формата файла. Проверьте структуру JSON.',
      );
    }

    if (decoded is! List) {
      throw const DataException(
        'Ошибка формата файла. Проверьте структуру JSON: '
        'корневой элемент должен быть массивом.',
      );
    }

    final points = <WiFiPoint>[];
    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i];
      if (item is! Map<String, dynamic>) {
        throw DataException(
          'Ошибка формата файла. Проверьте структуру JSON: '
          'элемент #$i не является объектом.',
        );
      }
      points.add(WiFiPoint.fromJson(item));
    }
    return points;
  }
}