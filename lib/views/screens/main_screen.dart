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
import '../../viewmodels/map_provider_model.dart';
import '../widgets/wifi_marker_widget.dart';
import '../../exceptions/data_exception.dart';
import '../widgets/bottom_sheet_widget.dart';
import 'map_provider_screen.dart';

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

  final _sheetController = DraggableScrollableController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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
  // Навигация и обработка действий из Drawer
  // ---------------------------------------------------------------------------

  void _handleMenuAction(String value, MapViewModel viewModel) async {
    // Закрываем Drawer перед выполнением действия
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    switch (value) {
      case 'add':
        await _showAddPointDialog(viewModel);
        break;
      case 'import':
        await viewModel.pickAndLoadDatabase();
        break;
      case 'export':
        await viewModel.exportDatabase();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Выберите приложение для экспорта базы')),
          );
        }
        break;
      case 'sync_url':
        await _showSyncUrlDialog();
        break;
      case 'sync':
        await _synchronize();
        break;
      case 'location':
        await viewModel.refreshUserLocation();
        break;
      case 'provider':
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const MapProviderScreen(),
            ),
          );
        }
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Ошибки и диалоги
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
    setState(() {
      if (_selectedPoint == point) {
        _selectedPoint = null;
      } else {
        _selectedPoint = point;
      }
    });

    if (_selectedPoint != null){
      final screenHeight = MediaQuery.of(context).size.height;
      context.read<MapViewModel>().focusOnPoint(point, screenHeight, _currentZoom);
    }
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
        _showSyncDialog(result, viewModel);
        break;

      case SyncStatus.error:
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
      key: _scaffoldKey, // Устанавливаем ключ для контроля Drawer
      endDrawer: Consumer<MapViewModel>( // endDrawer открывается справа (как и старое PopupMenu)
        builder: (context, viewModel, _) => _buildNavigationDrawer(viewModel),
      ),
      body: Consumer<MapViewModel>(
        builder: (context, viewModel, _) {
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
  // Компоненты UI (Карта, Панели, Drawer)
  // ---------------------------------------------------------------------------

  Widget _buildMap(MapViewModel viewModel) {
    final userLatLng = viewModel.userLatLng;
    final providerModel = context.watch<MapProviderModel>();
    final currentProvider = providerModel.currentProvider;
    final urlTemplate = providerModel.currentUrlTemplate;

    // Use FMTC tile provider only for OSM (and on non-web), otherwise use NetworkTileProvider
    final tileProvider = (currentProvider.id == 'osm')
        ? _tileProvider
        : NetworkTileProvider();

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
        TileLayer(
          urlTemplate: urlTemplate,
          userAgentPackageName: 'com.example.mapfi',
          tileProvider: tileProvider,
        ),
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
                        color: const Color.fromARGB(255, 22, 160, 133).withValues(alpha: 0.4),
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
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ],
                        ),
                      ),
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
              // Кнопка вызова Drawer
              Material(
                elevation: 4,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(24),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(24),
                ),
                color: theme.colorScheme.surface,
                child: IconButton(
                  icon: const FaIcon(FontAwesomeIcons.ellipsisVertical, size: 18),
                  tooltip: 'Меню управления',
                  onPressed: () {
                    _scaffoldKey.currentState?.openEndDrawer();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationDrawer(MapViewModel viewModel) {
    final theme = Theme.of(context);

    return NavigationDrawer(
      backgroundColor: theme.colorScheme.surface,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 16, 16),
          child: Text(
            'MapFi',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.plus, size: 20),
          label: Text('Добавить точку', style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.folderOpen, size: 20),
          label: Text('Импорт данных', style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.download, size: 20),
          label: Text('Экспорт данных', style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.link, size: 20),
          label: Text('URL репозитория', style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.rotate, size: 20),
          label: Text('Синхронизировать', style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.locationCrosshairs, size: 20),
          label: Text('Моё местоположение', style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.map, size: 20),
          label: Text('Провайдер карты', style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
      ],
      onDestinationSelected: (index) {
        // Карта соответствия индексов Drawer и строковых команд
        final actions = ['add', 'import', 'export', 'sync_url', 'sync', 'location', 'provider'];
        _handleMenuAction(actions[index], viewModel);
      },
    );
  }
}