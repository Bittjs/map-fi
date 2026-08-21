// lib/services/device_identity_service.dart

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../exceptions/data_exception.dart';

/// Результат формирования идентификатора устройства для бэкенда.
class DeviceIdentity {
  /// Исходный уникальный ID устройства (UUID или аппаратный хэш)
  final String rawId;

  /// Хэш SHA-256 в виде hex-строки (64 символа)
  final String hexHash;

  /// Хэш SHA-256 в бинарном виде (32 байта, под структуру PostgreSQL: BYTEA NOT NULL UNIQUE)
  final Uint8List binaryHash;

  const DeviceIdentity({
    required this.rawId,
    required this.hexHash,
    required this.binaryHash,
  });

  @override
  String toString() => 'DeviceIdentity(rawId: $rawId, hexHash: $hexHash)';
}

/// Сервис управления идентификатором устройства.
///
/// ВАЖНО: Согласно требованиям безопасности и защиты от спама,
/// идентификатор создается ЛЕНИВО — исключительно в момент, когда
/// пользователь явно совершает действие (например, выбирает добавить точку в БД).
class DeviceIdentityService {
  static const String _storageKeyDeviceId = 'mapfi_device_id_v1';
  static const String _appSalt = 'mapfi_secure_device_salt_2026';
  static const MethodChannel _channel = MethodChannel('com.example.mapfi/device_id');

  final FlutterSecureStorage _secureStorage;

  DeviceIdentityService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  /// Проверяет, был ли уже создан идентификатор устройства,
  /// НЕ создавая его, если его ещё нет.
  Future<bool> hasDeviceId() async {
    if (kIsWeb) return false;
    try {
      final existingId = await _secureStorage.read(key: _storageKeyDeviceId);
      return existingId != null && existingId.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Получает существующий или ГЕНЕРИРУЕТ НОВЫЙ идентификатор устройства.
  ///
  /// Вызывать ТОЛЬКО при явном действии пользователя (например, добавление точки).
  Future<DeviceIdentity> getOrCreateDeviceIdentity() async {
    if (kIsWeb) {
      throw const DataException('Добавление точек недоступно в веб-версии.');
    }

    String? deviceId = await _readDeviceIdFromSecureStorage();

    if (deviceId == null || deviceId.isEmpty) {
      deviceId = await _generatePersistentDeviceId();
      await _secureStorage.write(key: _storageKeyDeviceId, value: deviceId);
    }

    return _buildIdentityFromRawId(deviceId);
  }

  /// Чтение сохраненного ID из Keychain / SecureStorage
  Future<String?> _readDeviceIdFromSecureStorage() async {
    try {
      return await _secureStorage.read(key: _storageKeyDeviceId);
    } catch (_) {
      return null;
    }
  }

  /// Генерация нового стойкого UUID или получение аппаратного DRM ID (для Android)
  Future<String> _generatePersistentDeviceId() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final String? widevineId = await _channel.invokeMethod<String>('getWidevineId');
        if (widevineId != null && widevineId.isNotEmpty) {
          return widevineId;
        }
      } catch (_) {
        // Игнорируем и делаем фоллбек на UUID (например, в эмуляторах без DRM)
      }
    }

    // Для iOS, Desktop и неподдерживаемых Android-эмуляторов генерируем UUID v4.
    // На iOS он автоматически сохранится в Keychain и переживет переустановку.
    return const Uuid().v4();
  }

  /// Вычисление SHA-256 хэша (32 байта) от rawDeviceId + salt
  DeviceIdentity _buildIdentityFromRawId(String rawId) {
    final saltedInput = '$rawId:$_appSalt';
    final bytes = utf8.encode(saltedInput);
    final digest = sha256.convert(bytes);

    final hexHash = digest.toString();
    final binaryHash = Uint8List.fromList(digest.bytes);

    return DeviceIdentity(
      rawId: rawId,
      hexHash: hexHash,
      binaryHash: binaryHash,
    );
  }

  /// Очистка идентификатора (для тестов / отладки)
  Future<void> debugClear() async {
    try {
      await _secureStorage.delete(key: _storageKeyDeviceId);
    } catch (_) {}
  }
}
