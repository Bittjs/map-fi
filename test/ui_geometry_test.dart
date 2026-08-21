// test/ui_geometry_test.dart
// Проверка графических фиксов:
//   1. Drawer (endDrawer) прижат к правому краю, занимает всю высоту,
//      футер с токеном — внутри границ (не вылезает и не по центру).
//   2. Карточка фидбека (PointFeedbackBar) появляется сразу под выбранной
//      точкой в списке, а не вверху панели.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mapfi/models/wifi_point.dart';
import 'package:mapfi/viewmodels/map_viewmodel.dart';
import 'package:mapfi/views/widgets/point_feedback_bar.dart';
import 'package:mapfi/views/widgets/side_panel_widget.dart';
import 'package:provider/provider.dart';

import 'fakes/fake_point_store.dart';

/// Отключает платформенный канал геолокации, иначе в widget-тестах
/// `Geolocator.isLocationServiceEnabled()` висит (плагин не отвечает).
void _mockGeolocator(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/geolocator'),
    (call) async => false,
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/geolocator'), null));
}

/// Структура endDrawer после фикса: один NavigationDrawer с footer.
/// Ярлыки короткие, чтобы тестовый шрифт (Ahem) не давал overflow — это не
/// влияет на геометрию шторки.
Widget _drawerStructure() {
  final colors = ThemeData().colorScheme;
  return NavigationDrawer(
    backgroundColor: colors.surface,
    footer: Container(
      width: double.infinity,
      color: colors.surface,
      child: const SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Divider(height: 1),
              SizedBox(height: 10),
              Text('Токен устройства', style: TextStyle(fontSize: 12)),
              SizedBox(height: 6),
              Text('token-abc', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    ),
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(28, 32, 16, 16),
        child: Text('MapFi'),
      ),
      for (final label in ['A', 'B', 'C', 'D', 'E', 'F', 'G'])
        NavigationDrawerDestination(
          icon: const Icon(Icons.circle, size: 20),
          label: Text(label),
        ),
    ],
  );
}

WiFiPoint _point(String id, String name) => WiFiPoint(
      id: id,
      name: name,
      password: '',
      rating: 5,
      lat: 55.0,
      lng: 82.9,
    );

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('drawer прижат справа, полная высота, футер в границах (phone)',
      (tester) async {
    const size = Size(390, 844);
    await _setSurface(tester, size);

    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          body: const ColoredBox(color: Colors.blue),
          endDrawer: _drawerStructure(),
        ),
      ),
    );

    scaffoldKey.currentState!.openEndDrawer();
    await tester.pumpAndSettle();

    final drawerRect = tester.getRect(find.byType(NavigationDrawer));
    final footerRect = tester.getRect(find.text('Токен устройства'));

    // Прижат к правому краю: левый край = ширина экрана − 304.
    expect(drawerRect.left, closeTo(size.width - 304.0, 0.5));
    expect(drawerRect.width, closeTo(304.0, 0.5));
    // Полная высота.
    expect(drawerRect.top, 0);
    expect(drawerRect.bottom, closeTo(size.height, 0.5));
    // Футер внутри границ шторки.
    expect(footerRect.top, greaterThan(drawerRect.top));
    expect(footerRect.bottom, lessThanOrEqualTo(size.height));
  });

  testWidgets('drawer прижат справа, полная высота, футер в границах (wide)',
      (tester) async {
    const size = Size(1280, 800);
    await _setSurface(tester, size);

    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          body: const ColoredBox(color: Colors.blue),
          endDrawer: _drawerStructure(),
        ),
      ),
    );

    scaffoldKey.currentState!.openEndDrawer();
    await tester.pumpAndSettle();

    final drawerRect = tester.getRect(find.byType(NavigationDrawer));
    final footerRect = tester.getRect(find.text('Токен устройства'));

    expect(drawerRect.left, closeTo(size.width - 304.0, 0.5));
    expect(drawerRect.width, closeTo(304.0, 0.5));
    expect(drawerRect.top, 0);
    expect(drawerRect.bottom, closeTo(size.height, 0.5));
    expect(footerRect.top, greaterThan(drawerRect.top));
    expect(footerRect.bottom, lessThanOrEqualTo(size.height));
  });

  testWidgets('карточка фидбека появляется сразу под выбранной точкой',
      (tester) async {
    const size = Size(400, 800);
    await _setSurface(tester, size);
    _mockGeolocator(tester);

    final store = FakePointStore();
    store.points.addAll([
      for (var i = 1; i <= 12; i++)
        _point('$i', 'Сеть $i'),
    ]);
    final viewModel = MapViewModel(store: store);
    await viewModel.init();

    final selected = store.points[2]; // «Сеть 3»
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: viewModel,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: WiFiSidePanel(
                selectedPoint: selected,
                onPointTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barFinder = find.byType(PointFeedbackBar);
    expect(barFinder, findsOneWidget);

    final barRect = tester.getRect(barFinder);
    final tileRect = tester.getRect(find.widgetWithText(ListTile, selected.name));

    // Карточка сразу под выбранным тайлом.
    expect(barRect.top, closeTo(tileRect.bottom, 1.0));
    // И НЕ вверху панели (ниже строки сортировки).
    expect(barRect.top, greaterThan(60));
  });
}