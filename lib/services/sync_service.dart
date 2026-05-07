// lib/services/sync_service.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../exceptions/mapfi_data_exception.dart';
import '../models/wifi_point.dart';
import '../repositories/wifi_repository.dart';

/// Результат синхронизации с GitHub.
enum SyncStatus {
  /// Сервер вернул 304 — файл не изменился, обновление не требуется.
  notModified,

  /// Загружены новые данные — предложить пользователю применить их.
  newDataAvailable,

  /// Сетевая или серверная ошибка.
  error,
}

class SyncResult {
  final SyncStatus status;
  final List<WiFiPoint> points;
  final String? errorMessage;

  const SyncResult._(this.status, this.points, this.errorMessage);

  factory SyncResult.notModified() =>
      const SyncResult._(SyncStatus.notModified, [], null);

  factory SyncResult.newData(List<WiFiPoint> points) =>
      SyncResult._(SyncStatus.newDataAvailable, points, null);

  factory SyncResult.error(String message) =>
      SyncResult._(SyncStatus.error, [], message);
}

/// Сервис синхронизации базы точек через публичный GitHub-репозиторий.
/// Поддерживает ETag для экономии трафика.
class SyncService {
  static const _prefKeyUrl = 'sync_url';
  static const _prefKeyEtag = 'sync_etag';

  final WiFiRepository _repository;

  SyncService(this._repository);

  // ---------------------------------------------------------------------------
  // URL репозитория
  // ---------------------------------------------------------------------------

  Future<String?> getSyncUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyUrl);
  }

  Future<void> setSyncUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyUrl, url);
  }

  // ---------------------------------------------------------------------------
  // Синхронизация
  // ---------------------------------------------------------------------------

  /// Скачивает JSON с сервера и сравнивает с локальными данными.
  /// При совпадении ETag возвращает [SyncStatus.notModified] без парсинга.
  Future<SyncResult> synchronize() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_prefKeyUrl);
    if (url == null || url.isEmpty) {
      return SyncResult.error('URL репозитория не задан. '
          'Укажите его в настройках приложения.');
    }

    final rawUrl = _toRawUrl(url);

    try {
      final savedEtag = prefs.getString(_prefKeyEtag);

      final headers = <String, String>{};
      if (savedEtag != null) {
        headers['If-None-Match'] = savedEtag;
      }

      final response = await http
          .get(Uri.parse(rawUrl), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 304) {
        // Файл не изменился
        return SyncResult.notModified();
      }

      if (response.statusCode != 200) {
        return SyncResult.error(
          'Ошибка сервера: HTTP ${response.statusCode}.',
        );
      }

      // Сохраняем ETag для следующего запроса
      final newEtag = response.headers['etag'];
      if (newEtag != null) {
        await prefs.setString(_prefKeyEtag, newEtag);
      }

      final bytes = Uint8List.fromList(response.bodyBytes);
      final remotePoints = _repository.parseFromBytes(bytes);

      return SyncResult.newData(remotePoints);
    } on MapFiDataException catch (e) {
      return SyncResult.error(e.message);
    } catch (e) {
      return SyncResult.error('Не удалось подключиться к серверу: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Вспомогательное
  // ---------------------------------------------------------------------------

  /// Конвертирует обычный GitHub-URL в raw.githubusercontent.com, если нужно.
  String _toRawUrl(String url) {
    // Уже raw-ссылка
    if (url.contains('raw.githubusercontent.com')) return url;

    // https://github.com/user/repo/blob/branch/file.json
    //   → https://raw.githubusercontent.com/user/repo/branch/file.json
    return url
        .replaceFirst('github.com', 'raw.githubusercontent.com')
        .replaceFirst('/blob/', '/');
  }
}
