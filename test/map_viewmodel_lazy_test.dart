// test/map_viewmodel_lazy_test.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfi/services/device_identity_service.dart';
import 'package:mapfi/viewmodels/map_viewmodel.dart';

import 'fakes/fake_point_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('MapViewModel does NOT initialize or generate Device ID during constructor or startup', () async {
    final identityService = DeviceIdentityService();
    
    // Сначала проверим, что ID нет
    expect(await identityService.hasDeviceId(), isFalse);

    // Создаем ViewModel
    final viewModel = MapViewModel(
      deviceIdentityService: identityService,
      store: FakePointStore(),
    );

    // После создания ViewModel, ID всё ещё НЕ должен быть создан (так как генерация ленивая!)
    expect(await identityService.hasDeviceId(), isFalse);

    // Попытаемся инициализировать (загрузить точки из хранилища и т.д.)
    try {
      await viewModel.init();
    } catch (_) {
      // Игнорируем возможные системные ошибки плагинов в среде тестов
    }

    // Даже после инициализации ID всё ещё НЕ должен быть создан
    expect(await identityService.hasDeviceId(), isFalse);
  });
}
