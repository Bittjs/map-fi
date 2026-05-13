// lib/services/sync_service.dart
//Синхронизация с в нешним файлом
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../exceptions/data_exception.dart';
import '../models/wifi_point.dart';
import 'repository_service.dart';

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
  final dynamic exception;

  const SyncResult._(this.status, this.points, this.errorMessage, this.exception);

  factory SyncResult.notModified() =>
      const SyncResult._(SyncStatus.notModified, [], null, null);

  factory SyncResult.newData(List<WiFiPoint> points) =>
      SyncResult._(SyncStatus.newDataAvailable, points, null, null);

  factory SyncResult.error(String message, [dynamic exception]) =>
      SyncResult._(SyncStatus.error, [], message, exception);
}

/// Сервис синхронизации базы точек через публичный GitHub-репозиторий.
/// Поддерживает ETag для экономии трафика.
class SyncService {
  static const _prefKeyUrl = 'sync_url';
  static const _prefKeyEtag = 'sync_etag';

  final WiFiRepository _repository;

  SyncService(this._repository);

  //URL файла
  Future<String?> getSyncUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyUrl);
  }

  Future<void> setSyncUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyUrl, url);
  }

  //Синхронизация
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

      //Сохраняется ETag для следующего запроса
      final newEtag = response.headers['etag'];
      if (newEtag != null) {
        await prefs.setString(_prefKeyEtag, newEtag);
      }

      final bytes = Uint8List.fromList(response.bodyBytes);
      final remotePoints = _repository.parseFromBytes(bytes);

      return SyncResult.newData(remotePoints);
    } on DataException catch (e) {
      return SyncResult.error(e.message);
    } catch (e) {
      return SyncResult.error('Не удалось подключиться к серверу: $e', e);
    }
  }

  //Вспомогательное преобразование
  //TODO - держать в уме при добавлении проддержки других ссылок
  String _toRawUrl(String url) {
    if (url.contains('raw.githubusercontent.com')) return url;

    // https://github.com/user/repo/blob/branch/file.json
    //   → https://raw.githubusercontent.com/user/repo/branch/file.json
    return url
        .replaceFirst('github.com', 'raw.githubusercontent.com')
        .replaceFirst('/blob/', '/');
  }
}
