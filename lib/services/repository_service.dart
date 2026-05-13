// lib/services/repository_service.dart
// Хранение точек Wi-Fi в локальном файле (points.json)
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../exceptions/data_exception.dart';
import '../models/wifi_point.dart';

class WiFiRepository {
  //TODO - явно менять на любые джсоны
  static const _fileName = 'points.json';

  //Путь к файлу
  Future<File> get _localFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  //Чтение
  Future<List<WiFiPoint>> loadPoints() async {
    final file = await _localFile;
    if (!file.existsSync()) return [];
    final bytes = await file.readAsBytes();
    return _parseBytes(bytes);
  }

  // Парсит точки из сырых байтов (для импорта через file_picker)
  List<WiFiPoint> parseFromBytes(Uint8List bytes) => _parseBytes(bytes);

  //Запись
  Future<void> savePoints(List<WiFiPoint> points) async {
    final file = await _localFile;
    final data = jsonEncode(points.map((p) => p.toJson()).toList());
    await file.writeAsString(data, flush: true);
  }

  //Парсинг
  List<WiFiPoint> _parseBytes(Uint8List bytes) {
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
      // WiFiPoint.fromJson сам бросит MapFiDataException при недостающих полях
      points.add(WiFiPoint.fromJson(item));
    }
    return points;
  }
}
