// lib/models/api_models.dart
// DTO для взаимодействия с бэкендом (server/main.go)

import 'wifi_point.dart';

/// Ответ POST /api/v1/auth/device
class AuthSession {
  final String userId;
  final String role;

  const AuthSession({required this.userId, required this.role});

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        userId: json['user_id'] as String,
        role: json['role'] as String,
      );
}

/// Точка доступа с бэкенда (PointResponse)
class ApiPoint {
  final String id;
  final int regionId;
  final String ssid;
  final String password;
  final String datasetType;
  final double lat;
  final double lon;
  final bool isDeleted;
  final DateTime updatedAt;
  final int upvotes;
  final int downvotes;

  const ApiPoint({
    required this.id,
    required this.regionId,
    required this.ssid,
    required this.password,
    required this.datasetType,
    required this.lat,
    required this.lon,
    required this.isDeleted,
    required this.updatedAt,
    this.upvotes = 0,
    this.downvotes = 0,
  });

  factory ApiPoint.fromJson(Map<String, dynamic> json) => ApiPoint(
        id: json['id'] as String,
        regionId: (json['region_id'] as num).toInt(),
        ssid: json['ssid'] as String,
        password: (json['password'] as String?) ?? '',
        datasetType: json['dataset_type'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        isDeleted: (json['is_deleted'] as bool?) ?? false,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        upvotes: (json['upvotes'] as num?)?.toInt() ?? 0,
        downvotes: (json['downvotes'] as num?)?.toInt() ?? 0,
      );

  /// Конвертация в локальную модель приложения.
  /// Рейтинг — разность проверок и жалоб (для сортировки «Сначала Лучшие»).
  WiFiPoint toWiFiPoint() => WiFiPoint(
        id: id,
        name: ssid,
        password: password,
        rating: (upvotes - downvotes).toDouble(),
        lat: lat,
        lng: lon,
        regionId: regionId,
        datasetType: datasetType,
      );
}

/// Ответ GET /api/v1/sync
class ServerSync {
  final DateTime serverTime;
  final List<ApiPoint> points;

  const ServerSync({required this.serverTime, required this.points});

  factory ServerSync.fromJson(Map<String, dynamic> json) => ServerSync(
        serverTime: DateTime.parse(json['server_time'] as String),
        points: (json['points'] as List)
            .map((e) => ApiPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}