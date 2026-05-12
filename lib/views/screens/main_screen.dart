// lib/views/screens/main_screen.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart'; 
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../models/wifi_point.dart';
import '../../services/sync_service.dart';
import '../../viewmodels/map_viewmodel.dart';
import '../widgets/wifi_marker_widget.dart';
import '../../exceptions/data_exception.dart';
import '../widgets/bottom_sheet_widget.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with TickerProviderStateMixin {

  late final TileProvider _tileProvider;

  // Контроллер анимированной карты
  late AnimatedMapController _mapController;

  // ---- Исправление Ошибки 3: PageStorageKey + DraggableScrollableController --
  final _sheetKey = const PageStorageKey<String>('bottom_sheet');
  final _sheetController = DraggableScrollableController();

  // Текущий зум (для расчёта смещения)
  double _currentZoom = 12.0;

  // Выбранная точка (для подсветки маркера)
  WiFiPoint? _selectedPoint;

  // Текст поиска
  final _searchController = TextEditingController();

  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _mapController = AnimatedMapController(vsync: this);

    if (kIsWeb) {
      _tileProvider = NetworkTileProvider();
    } else {
      _tileProvider = FMTCTileProvider(stores: 
      const {'mapStore': BrowseStoreStrategy.readUpdateCreate});
    }
    // Передаём контроллер в ViewModel
    final viewModel = context.read<MapViewModel>();
    viewModel.mapController = _mapController;

    // Инициализируем данные
    viewModel.init().then((_) => _checkError(viewModel));

    // Слушаем изменение размера шторки → обновляем ViewModel
    _sheetController.addListener(() {
      viewModel.updateSheetSize(_sheetController.size);
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    _sheetController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Ошибка 1: показываем AlertDialog при ошибке JSON
  // ---------------------------------------------------------------------------

  void _checkError(MapViewModel vm) {
    if (vm.lastError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showErrorDialog(vm.lastError!);
        vm.clearError();
      });
    }
  }

  void _showErrorDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ошибка'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ОК'),
          ),
        ],
      ),
    );
  }

  void _focusOnPoint(WiFiPoint point) {
    setState(() => _selectedPoint = point);
    final screenHeight = MediaQuery.of(context).size.height;
    context.read<MapViewModel>().focusOnPoint(point, screenHeight, _currentZoom);
  }

  Future<void> _synchronize() async {
    final viewModel = context.read<MapViewModel>();
    final result = await viewModel.synchronize();
    if (!mounted) return;

    switch (result.status) {
      case SyncStatus.notModified:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('База данных актуальна.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        break;

      case SyncStatus.newDataAvailable:
        // Сначала спрашиваем пользователя через диалог
        _showSyncDialog(result, viewModel);
        break;

      case SyncStatus.error:
        // Формируем красивый текст ошибки
        String errorMessage = result.errorMessage ?? 'Ошибка синхронизации';
        
        if (result.exception is DataException) {
          errorMessage = 'Ошибка структуры файла: ${(result.exception as DataException).message}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        break;
    }
  }

  void _showSyncDialog(SyncResult result, MapViewModel viewModel) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Доступно обновление'),
        content: Text(
          'На сервере найдено ${result.points.length} точек. '
          'Обновить локальную базу?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await viewModel.applySyncResult(result);
            },
            child: const Text('Обновить'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Диалог настройки URL GitHub
  // ---------------------------------------------------------------------------

  Future<void> _showSyncUrlDialog() async {
    final viewModel = context.read<MapViewModel>();
    final current = await viewModel.syncService.getSyncUrl() ?? '';
    if (!mounted) return;

    final controller = TextEditingController(text: current);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('URL репозитория'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://github.com/user/repo/blob/main/points.json',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(12)
                    )
                  )
                ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(24),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(24)
                    )
                  )
                ),
            onPressed: () async {
              await viewModel.syncService.setSyncUrl(controller.text.trim());
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

Future<void> _showAddPointDialog(MapViewModel viewModel) async {

  final passwordController = TextEditingController();

  await showDialog(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Добавить текущую сеть'),
        content: TextField(
          controller: passwordController,
          decoration: const InputDecoration(
            labelText: 'Пароль (необязательно)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [

          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),

          FilledButton(
            onPressed: () async {

              final ok = await viewModel.addNetworkPoint(
                password: passwordController.text.trim(),
              );

              if (!mounted) return;

              Navigator.pop(ctx);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ok
                      ? 'Точка успешно добавлена'
                      : (viewModel.lastError ?? 'Ошибка'),
                  ),
                ),
              );
            },
            child: const Text('Добавить'),
          ),
        ],
      );
    },
  );
}

  // ---------------------------------------------------------------------------
  // Построение UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<MapViewModel>(
        builder: (context, viewModel, _) {
          // Реакция на ошибку (не в initState — может прийти позже)
          if (viewModel.lastError != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showErrorDialog(viewModel.lastError!);
              viewModel.clearError();
            });
          }

          return Stack(
            children: [
              // ---- Карта (на весь экран) -----------------------------------
              _buildMap(viewModel),

              // ---- Прозрачный AppBar ---------------------------------------
              _buildTopBar(viewModel),

              // ---- Нижняя шторка -------------------------------------------
              WiFiBottomSheet(
                controller: _sheetController,
                selectedPoint: _selectedPoint,
                onPointTap: _focusOnPoint,
              ),

              if (viewModel.isLoading)
                const Positioned(
                  top: 80,
                  left: 0,
                  right: 0,
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          );
        },
      ),
    );
  }
  // ---------------------------------------------------------------------------
  // Карта с кешированием тайлов
  // ---------------------------------------------------------------------------

  Widget _buildMap(MapViewModel viewModel) {
    final userLatLng = viewModel.userLatLng;

    return FlutterMap(
      mapController: _mapController.mapController,
      options: MapOptions(
        initialCenter: userLatLng ?? const LatLng(55.0, 82.9),
        initialZoom: _currentZoom,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
        onMapEvent: (event) {
          if (event is MapEventMoveEnd || event is MapEventScrollWheelZoom) {
            setState(() {
              _currentZoom = _mapController.mapController.camera.zoom;
            });
          }
        },
      ),
      children: [
        // Офлайн-кеширование через flutter_map_tile_caching
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.mapfi',
          tileProvider: _tileProvider,
          // Рекомендуется задать maxZoom и другие опции, если нужно
        ),

        // Маркеры точек Wi-Fi
        MarkerLayer(
          markers: viewModel.points.map((point) {
            return Marker(
              point: point.location,
              width: 80,
              height: 60,
              child: WiFiMarkerWidget(
                rotation: -_mapController.mapController.camera.rotationRad,
                point: point,
                isHighlighted: point == _selectedPoint,
                onTap: () => _focusOnPoint(point),
              ),
            );
          }).toList(),
        ),

        // Маркер пользователя
        if (userLatLng != null)
          MarkerLayer(
            markers: [
              Marker(
                point: userLatLng,
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 22, 160, 133),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: const Color.fromARGB(255, 22, 160, 133).withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Верхняя панель (прозрачный AppBar)
  // ---------------------------------------------------------------------------

  Widget _buildTopBar(MapViewModel viewModel) {
    final theme = Theme.of(context);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Поиск
              Expanded(
  child: Material(
    elevation: 4,
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(24),
      topRight: Radius.circular(12),
      bottomLeft: Radius.circular(24),
      bottomRight: Radius.circular(12),
    ),
    color: theme.colorScheme.surface,
    child: TextField(
      controller: _searchController,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        hintText: 'Поиск сети',
        hintStyle: TextStyle(color: theme.colorScheme.onSurface),
        
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 16.0, right: 12.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FaIcon(
                FontAwesomeIcons.magnifyingGlass,
                size: 18,
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ],
          ),
        ),
                      
                      // --- СУФФИКС (КНОПКА ОЧИСТКИ) ---
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: FaIcon(
                                FontAwesomeIcons.xmark,
                                size: 16,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                viewModel.setSearchQuery('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      
                      contentPadding: const EdgeInsets.symmetric(vertical: 14), 
                    ),
                    onChanged: viewModel.setSearchQuery,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Меню отладки
              Material(
                elevation: 4,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(24),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(24)
                  ),
                color: theme.colorScheme.surface,
                child: PopupMenuButton<String>(
                  icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 18,),
                  tooltip: 'Меню',
                  onSelected: (value) async {
                    switch (value) {
                      case 'add':
                      await _showAddPointDialog(viewModel);
                      case 'import':
                        await viewModel.pickAndLoadDatabase();
                      case 'export':
                        await viewModel.exportDatabase();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Выберите приложение для экспорта базы')),
                          );
                        }
                      case 'sync_url':
                        await _showSyncUrlDialog();
                      case 'sync':
                        await _synchronize();
                      case 'location':
                        await viewModel.refreshUserLocation();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: "add", 
                      child: ListTile(
                        leading: FaIcon(FontAwesomeIcons.plus),
                        title: Text("Добавить точку"),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'import',
                      child: ListTile(
                        leading: FaIcon(FontAwesomeIcons.folderOpen),
                        title: Text('Импорт данных'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'export',
                      child: ListTile(
                        leading: FaIcon(FontAwesomeIcons.download),
                        title: Text('Экспорт данных'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'sync_url',
                      child: ListTile(
                        leading: FaIcon(FontAwesomeIcons.link),
                        title: Text('URL репозитория'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'sync',
                      child: ListTile(
                        leading: FaIcon(FontAwesomeIcons.rotate),
                        title: Text('Синхронизировать'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'location',
                      child: ListTile(
                        leading: FaIcon(FontAwesomeIcons.locationCrosshairs),
                        title: Text('Обновить местоположение'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Нижняя шторка (исправление Ошибки 3: PageStorageKey)
  // ---------------------------------------------------------------------------
}