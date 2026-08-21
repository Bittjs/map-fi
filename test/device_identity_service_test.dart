// test/device_identity_service_test.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfi/services/device_identity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('hasDeviceId returns false initially (does NOT generate ID automatically)', () async {
    final service = DeviceIdentityService();
    
    final hasId = await service.hasDeviceId();
    expect(hasId, isFalse);
  });

  test('getOrCreateDeviceIdentity generates ID lazily on-demand', () async {
    final service = DeviceIdentityService();

    // Перед вызовом ID нет
    expect(await service.hasDeviceId(), isFalse);

    // Первичный вызов - генерирует ID
    final identity = await service.getOrCreateDeviceIdentity();

    expect(identity.rawId, isNotEmpty);
    expect(identity.hexHash.length, equals(64)); // SHA-256 in hex
    expect(identity.binaryHash.length, equals(32)); // SHA-256 in 32 bytes (BYTEA)

    // После вызова ID теперь существует
    expect(await service.hasDeviceId(), isTrue);
  });

  test('getOrCreateDeviceIdentity returns the SAME identity on subsequent calls', () async {
    final service = DeviceIdentityService();

    final firstIdentity = await service.getOrCreateDeviceIdentity();
    final secondIdentity = await service.getOrCreateDeviceIdentity();

    expect(secondIdentity.rawId, equals(firstIdentity.rawId));
    expect(secondIdentity.hexHash, equals(firstIdentity.hexHash));
    expect(secondIdentity.binaryHash, equals(firstIdentity.binaryHash));
  });

  test('debugClear removes stored device ID', () async {
    final service = DeviceIdentityService();

    await service.getOrCreateDeviceIdentity();
    expect(await service.hasDeviceId(), isTrue);

    await service.debugClear();
    expect(await service.hasDeviceId(), isFalse);
  });
}
