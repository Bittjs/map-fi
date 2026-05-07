// lib/models/wifi_point.dart

import 'package:latlong2/latlong.dart';
import '../exceptions/mapfi_data_exception.dart';

/// Модель одной точки Wi-Fi.
/// Поля: id, name, password, rating, lat, lng.
class WiFiPoint {
  final String id;
  final String name;
  final String password;
  final double rating;
  final double lat;
  final double lng;

  const WiFiPoint({
    required this.id,
    required this.name,
    required this.password,
    required this.rating,
    required this.lat,
    required this.lng,
  });

  /// Географические координаты для flutter_map.
  LatLng get location => LatLng(lat, lng);

  // ---------------------------------------------------------------------------
  // Сериализация
  // ---------------------------------------------------------------------------

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

    if (id is! String || id.isEmpty) {
      throw MapFiDataException('Поле "id" должно быть непустой строкой.');
    }
    if (name is! String || name.isEmpty) {
      throw MapFiDataException('Поле "name" должно быть непустой строкой.');
    }
    if (password is! String) {
      throw MapFiDataException('Поле "password" должно быть строкой.');
    }
    if (rating is! num) {
      throw MapFiDataException('Поле "rating" должно быть числом.');
    }
    if (lat is! num) {
      throw MapFiDataException('Поле "lat" должно быть числом.');
    }
    if (lng is! num) {
      throw MapFiDataException('Поле "lng" должно быть числом.');
    }

    return WiFiPoint(
      id: id,
      name: name,
      password: password,
      rating: (rating as num).toDouble(),
      lat: (lat as num).toDouble(),
      lng: (lng as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'password': password,
        'rating': rating,
        'lat': lat,
        'lng': lng,
      };

  // ---------------------------------------------------------------------------

  static void _requireField(Map<String, dynamic> json, String field) {
    if (!json.containsKey(field)) {
      throw MapFiDataException(
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
