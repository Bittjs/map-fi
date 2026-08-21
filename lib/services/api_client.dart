// lib/services/api_client.dart
// HTTP-клиент для бэкенда MapFi (server/main.go)

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_models.dart';
import '../models/app_regions.dart';
import '../models/point_stats.dart';
import 'server_settings.dart';

/// Ошибка API бэкенда (статус != 2xx или сетевой сбой)
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Типы отзывов (зеркалит enum feedback_type в server/setup/001_init.sql)
abstract final class FeedbackTypes {
  static const verify = 'verify';
  static const wrongPassword = 'wrong_password';
  static const pointNotFound = 'point_not_found';
  static const spamFake = 'spam_fake';
  static const other = 'other';
}

/// Клиент для REST API v1.
///
/// Адрес по умолчанию — [ServerSettings.baseUrl] (настраивается в
/// Предпочтениях, ключ `server_base_url`). Для тестов передаётся явно.
class ApiClient {
  final String? _explicitBaseUrl;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 15);

  ApiClient({String? baseUrl, http.Client? httpClient})
      : _explicitBaseUrl = baseUrl,
        _http = httpClient ?? http.Client();

  /// Текущий адрес: явно переданный в конструктор или из настроек.
  String get baseUrl => _explicitBaseUrl ?? ServerSettings.baseUrl;

  static String defaultBaseUrl() => ServerSettings.defaultBaseUrl;

  /// Регистрация/авторизация устройства.
  /// [deviceToken] — сырой идентификатор устройства (identity.rawId);
  /// бэкенд сам хэширует его SHA-256 и хранит в users.device_token_hash.
  Future<AuthSession> registerDevice(String deviceToken) async {
    final resp = await _post('/auth/device', {'device_token': deviceToken});
    return AuthSession.fromJson(_decodeMap(resp));
  }

  /// Дельта-синхронизация точек региона.
  /// [userId] (из [AuthSession.userId]) включает ролевой фильтр слоёв
  /// dataset_type на бэкенде.
  Future<ServerSync> syncPoints({
    required int regionId,
    DateTime? since,
    String? userId,
  }) async {
    final query = <String, String>{'region_id': '$regionId'};
    if (since != null) {
      query['since'] = since.toUtc().toIso8601String();
    }
    final headers = <String, String>{};
    if (userId != null) headers['X-User-ID'] = userId;
    final uri =
        Uri.parse('$baseUrl/api/v1/sync').replace(queryParameters: query);
    final resp = await _http.get(uri, headers: headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException(_parseError(resp), resp.statusCode);
    }
    return ServerSync.fromJson(_decodeMap(resp));
  }

  /// Список регионов с бэкенда (fallback — встроенный [kAppRegions]).
  Future<List<AppRegion>> fetchRegions() async {
    final resp = await _http
        .get(Uri.parse('$baseUrl/api/v1/regions'))
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException(_parseError(resp), resp.statusCode);
    }
    final data = _decodeMap(resp);
    return (data['regions'] as List)
        .map((e) => AppRegion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Агрегированные отзывы по точке за период [days] (по умолчанию 30).
  Future<PointStats> fetchPointStats({
    required String pointId,
    required int regionId,
    int days = 30,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/points/$pointId/stats').replace(
      queryParameters: {'region_id': '$regionId', 'days': '$days'},
    );
    final resp = await _http.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException(_parseError(resp), resp.statusCode);
    }
    return PointStats.fromJson(_decodeMap(resp));
  }

  /// Создание точки доступа (регион определяется бэкендом через PostGIS).
  Future<ApiPoint> createPoint({
    required String userId,
    required String ssid,
    String password = '',
    required double lat,
    required double lon,
    String datasetType = 'public',
  }) async {
    final resp = await _post(
      '/points',
      {
        'ssid': ssid,
        'password': password,
        'lat': lat,
        'lon': lon,
        'dataset_type': datasetType,
      },
      userId: userId,
    );
    if (resp.statusCode != 201) {
      throw ApiException(_parseError(resp), resp.statusCode);
    }
    return ApiPoint.fromJson(_decodeMap(resp));
  }

  /// Отправка отзыва по точке (verify / wrong_password / point_not_found / spam_fake / other).
  Future<void> createFeedback({
    required String userId,
    required String pointId,
    required int regionId,
    required String type,
  }) async {
    final resp = await _post(
      '/feedbacks',
      {'ap_id': pointId, 'region_id': regionId, 'type': type},
      userId: userId,
    );
    if (resp.statusCode != 201) {
      throw ApiException(_parseError(resp), resp.statusCode);
    }
  }

  // --- Внутренние помощники ---

  Future<http.Response> _post(
    String path,
    Map<String, dynamic> body, {
    String? userId,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (userId != null) headers['X-User-ID'] = userId;

    final resp = await _http
        .post(
          Uri.parse('$baseUrl/api/v1$path'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw ApiException(_parseError(resp), resp.statusCode);
    }
    return resp;
  }

  Map<String, dynamic> _decodeMap(http.Response resp) =>
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

  String _parseError(http.Response resp) {
    try {
      final data = _decodeMap(resp);
      return data['error']?.toString() ?? 'HTTP ${resp.statusCode}';
    } catch (_) {
      return 'HTTP ${resp.statusCode}';
    }
  }
}