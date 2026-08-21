// lib/models/wifi_point.dart
// Модель одной точки
import 'package:latlong2/latlong.dart';
import '../exceptions/data_exception.dart';

// Поля:
class WiFiPoint {
  final String id;
  final String name;
  final String password;
  final double rating;
  final double lat;
  final double lng;

  /// Регион точки (совпадает с region_id на бэкенде). 0 — «по умолчанию».
  final int regionId;

  /// Тип датасета (слой): public / volunteer_test / dev_test.
  final String datasetType;

  const WiFiPoint({
    required this.id,
    required this.name,
    required this.password,
    required this.rating,
    required this.lat,
    required this.lng,
    this.regionId = 0,
    this.datasetType = 'public',
  });

  LatLng get location => LatLng(lat, lng);

  //Сериализация
  factory WiFiPoint.fromJson(Map<String, dynamic> json) {
    _requireField(json, 'id');
    _requireField(json, 'name');
    _requireField(json, 'password');
    _requireField(json, 'rating');
    _requireField(json, 'lat');
    _requireField(json, 'lng');

    final id = json['id'];
    final name = json['name'];
    final password = json['password'];
    final rating = json['rating'];
    final lat = json['lat'];
    final lng = json['lng'];

    //Эксепшены
    if (id is! String || id.isEmpty) {
      throw const DataException('Поле "id" должно быть непустой строкой.');
    }
    if (name is! String || name.isEmpty) {
      throw const DataException('Поле "name" должно быть непустой строкой.');
    }
    if (password is! String) {
      throw const DataException('Поле "password" должно быть строкой.');
    }
    if (rating is! num) {
      throw const DataException('Поле "rating" должно быть числом.');
    }
    if (lat is! num) {
      throw const DataException('Поле "lat" должно быть числом.');
    }
    if (lng is! num) {
      throw const DataException('Поле "lng" должно быть числом.');
    }

    // Новые поля опциональны для обратной совместимости со старыми JSON-файлами
    final regionId = json['region_id'] ?? 0;
    if (regionId is! num) {
      throw const DataException('Поле "region_id" должно быть числом.');
    }
    final datasetType = json['dataset_type'] ?? 'public';
    if (datasetType is! String || datasetType.isEmpty) {
      throw const DataException(
          'Поле "dataset_type" должно быть непустой строкой.');
    }

    return WiFiPoint(
      id: id,
      name: name,
      password: password,
      rating: (rating).toDouble(),
      lat: (lat).toDouble(),
      lng: (lng).toDouble(),
      regionId: (regionId).toInt(),
      datasetType: datasetType,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'password': password,
        'rating': rating,
        'lat': lat,
        'lng': lng,
        'region_id': regionId,
        'dataset_type': datasetType,
      };

  static void _requireField(Map<String, dynamic> json, String field) {
    if (!json.containsKey(field)) {
      throw DataException(
        'Ошибка формата файла. Проверьте структуру JSON: '
        'отсутствует обязательное поле "$field".',
      );
    }
  }

  @override
  String toString() => 'WiFiPoint(id: $id, name: $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is WiFiPoint && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
