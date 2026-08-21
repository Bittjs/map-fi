// test/wifi_point_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mapfi/exceptions/data_exception.dart';
import 'package:mapfi/models/wifi_point.dart';

void main() {
  Map<String, dynamic> baseJson() => {
        'id': 'pt-1',
        'name': 'Cafe',
        'password': '1234',
        'rating': 4.5,
        'lat': 55.0,
        'lng': 82.9,
      };

  test('fromJson парсит новые поля region_id и dataset_type', () {
    final point = WiFiPoint.fromJson({
      ...baseJson(),
      'region_id': 54,
      'dataset_type': 'volunteer_test',
    });

    expect(point.regionId, 54);
    expect(point.datasetType, 'volunteer_test');
  });

  test('fromJson обратно совместим со старыми файлами (без новых полей)', () {
    final point = WiFiPoint.fromJson(baseJson());

    expect(point.regionId, 0, reason: 'Старый JSON без region_id → 0');
    expect(point.datasetType, 'public',
        reason: 'Старый JSON без dataset_type → public');
  });

  test('toJson содержит новые поля, round-trip сохраняет их', () {
    const point = WiFiPoint(
      id: 'pt-2',
      name: 'Metro',
      password: '',
      rating: 0,
      lat: 55.5,
      lng: 37.5,
      regionId: 77,
      datasetType: 'public',
    );

    final json = point.toJson();
    expect(json['region_id'], 77);
    expect(json['dataset_type'], 'public');

    final restored = WiFiPoint.fromJson(json);
    expect(restored.regionId, point.regionId);
    expect(restored.datasetType, point.datasetType);
  });

  test('неверный тип region_id → DataException', () {
    expect(
      () => WiFiPoint.fromJson({...baseJson(), 'region_id': 'not-a-number'}),
      throwsA(isA<DataException>()),
    );
  });
}