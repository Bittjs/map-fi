// lib/views/screens/main_screen.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../models/wifi_point.dart';
import '../../viewmodels/map_viewmodel.dart';
import '../../viewmodels/provider_viewmodel.dart';
import '../widgets/wifi_marker_widget.dart';
import '../widgets/bottom_sheet_widget.dart';
import '../widgets/side_panel_widget.dart';
import 'map_provider_screen.dart';
import 'preference_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
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
      _tileProvider = FMTCTileProvider(
          stores: const {'mapStore': BrowseStoreStrategy.readUpdateCreate});
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
      case 'preferences':
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const PreferencesScreen()),
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

    if (_selectedPoint != null) {
      final screenHeight = MediaQuery.of(context).size.height;
      context
          .read<MapViewModel>()
          .focusOnPoint(point, screenHeight, _currentZoom);
    }
  }

  Future<void> _synchronize() async {
    final viewModel = context.read<MapViewModel>();
    final count = await viewModel.synchronizeRegion(viewModel.selectedRegionId);
    if (!mounted) return;

    // При успехе показываем результат; ошибки отображаются встроенным диалогом
    // (через viewModel.lastError при пересборке).
    if (count != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count > 0
                ? 'Синхронизация завершена. Изменений: $count'
                : 'База данных актуальна.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
    final isWideScreen = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      key: _scaffoldKey, // Устанавливаем ключ для контроля Drawer
      endDrawer: Consumer<MapViewModel>(
        // endDrawer открывается справа (как и старое PopupMenu)
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

          return isWideScreen
              ? _buildWideLayout(viewModel)
              : _buildMobileLayout(viewModel);
        },
      ),
    );
  }

  Widget _buildMobileLayout(MapViewModel viewModel) {
    return Stack(
      children: [
        _buildMap(viewModel),
        _buildTopBar(viewModel),
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
  }

  Widget _buildWideLayout(MapViewModel viewModel) {
    return Row(children: [
      SizedBox(
        width: 400,
        child: WiFiSidePanel(
            selectedPoint: _selectedPoint, onPointTap: _focusOnPoint),
      ),
      Expanded(
        child: Stack(
          children: [
            _buildMap(viewModel),
            _buildTopBar(viewModel),
            if (viewModel.isLoading)
              const Positioned(
                top: 80,
                left: 0,
                right: 0,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      )
    ]);
  }
  // ---------------------------------------------------------------------------
  // Компоненты UI (Карта, Панели, Drawer)
  // ---------------------------------------------------------------------------

  Widget _buildMap(MapViewModel viewModel) {
    final userLatLng = viewModel.userLatLng;
    final providerModel = context.watch<MapProviderViewModel>();
    final currentProvider = providerModel.currentProvider;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final String urlTemplate =
        (isDarkMode && currentProvider.urlTemplateDark != null)
            ? providerModel.getFormattedUrl(currentProvider.urlTemplateDark!)
            : providerModel.currentUrlTemplate;

    final bool useDarkModeFilter = isDarkMode &&
        currentProvider.urlTemplateDark == null &&
        currentProvider.id != 'ewi';

    // Use FMTC tile provider only for OSM (and on non-web), otherwise use NetworkTileProvider
    final tileProvider =
        (currentProvider.id == 'osm') ? _tileProvider : NetworkTileProvider();

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
          userAgentPackageName: 'ru.sonar.mapfi',
          tileProvider: tileProvider,
          tileBuilder: useDarkModeFilter
              ? (context, tileWidget, tile) =>
                  darkModeTileBuilder(context, tileWidget, tile)
              : null,
        ),
        MarkerLayer(
          markers: viewModel.points.map((point) {
            return Marker(
              point: point.location,
              width: 80,
              height: 60,
              rotate: true,
              child: WiFiMarkerWidget(
                //rotation: -_mapController.mapController.camera.rotationRad,
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
                        color: const Color.fromARGB(255, 22, 160, 133)
                            .withValues(alpha: 0.4),
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
            child: Align(
          alignment: Alignment.topRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 500,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Поиск
                      Expanded(
                        child: Container(
                          height: 45,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(12),
                              bottomLeft: Radius.circular(24),
                              bottomRight: Radius.circular(12),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.2),
                                blurRadius: 0,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(
                                color: theme.colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Поиск сети',
                              hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurface),
                              prefixIcon: Padding(
                                padding: const EdgeInsets.only(
                                    left: 16.0, right: 12.0),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FaIcon(
                                      FontAwesomeIcons.magnifyingGlass,
                                      size: 18,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.8),
                                    ),
                                  ],
                                ),
                              ),
                              suffixIcon:
                                  _searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: FaIcon(
                                            FontAwesomeIcons.xmark,
                                            size: 16,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                          onPressed: () {
                                            _searchController.clear();
                                            viewModel.setSearchQuery('');
                                          },
                                        )
                                      : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 14),
                            ),
                            onChanged: viewModel.setSearchQuery,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Кнопка вызова Drawer
                      Container(
                        height: 45,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(24),
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(24),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.2),
                              blurRadius: 0,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: const FaIcon(FontAwesomeIcons.ellipsisVertical,
                              size: 18),
                          tooltip: 'Меню управления',
                          onPressed: () {
                            _scaffoldKey.currentState?.openEndDrawer();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Выбор региона
                  _buildRegionSelector(viewModel),
                ],
              ),
            ),
          ),
        )));
  }

  Widget _buildRegionSelector(MapViewModel viewModel) {
    final theme = Theme.of(context);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            blurRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            FontAwesomeIcons.mapLocationDot,
            size: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: viewModel.regions
                    .any((r) => r.id == viewModel.selectedRegionId)
                ? viewModel.selectedRegionId
                : null,
            underline: const SizedBox(),
            isDense: true,
            borderRadius: BorderRadius.circular(16),
            dropdownColor: theme.colorScheme.surface,
            iconEnabledColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.8),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            items: viewModel.regions
                .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
                .toList(),
            onChanged: _onRegionChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _onRegionChanged(int? regionId) async {
    if (regionId == null) return;
    final viewModel = context.read<MapViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final regionName = viewModel.regions.firstWhere((r) => r.id == regionId).name;

    viewModel.setSelectedRegionId(regionId);
    final count = await viewModel.synchronizeRegion(regionId);
    if (count == null) return; // ошибка отобразится диалогом через lastError

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? 'Регион: $regionName. Загружено изменений: $count'
              : 'Регион: $regionName. База актуальна.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildNavigationDrawer(MapViewModel viewModel) {
    final theme = Theme.of(context);

    return NavigationDrawer(
      backgroundColor: theme.colorScheme.surface,
      footer: _DeviceTokenFooter(viewModel: viewModel),
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
          label: Text('Добавить точку',
              style: TextStyle(color: theme.colorScheme.surface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.folderOpen, size: 20),
          label: Text('Импорт данных',
              style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.download, size: 20),
          label: Text('Экспорт данных',
              style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.rotate, size: 20),
          label: Text('Синхронизировать',
              style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.locationCrosshairs, size: 20),
          label: Text('Моё местоположение',
              style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.map, size: 20),
          label: Text('Провайдер карты',
              style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        NavigationDrawerDestination(
          icon: const FaIcon(FontAwesomeIcons.paintbrush, size: 20),
          label: Text('Предпочтения',
              style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
      ],
      onDestinationSelected: (index) {
        // Карта соответствия индексов Drawer и строковых команд
        final actions = [
          'add',
          'import',
          'export',
          'sync',
          'location',
          'provider',
          'preferences'
        ];
        _handleMenuAction(actions[index], viewModel);
      },
    );
  }
}

/// Футер Drawer: уникальный токен устройства (для копирования и разбана в БД).
class _DeviceTokenFooter extends StatefulWidget {
  final MapViewModel viewModel;

  const _DeviceTokenFooter({required this.viewModel});

  @override
  State<_DeviceTokenFooter> createState() => _DeviceTokenFooterState();
}

class _DeviceTokenFooterState extends State<_DeviceTokenFooter> {
  String? _token;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.getOrCreateDeviceToken().then((token) {
      if (!mounted) return;
      setState(() {
        _token = token;
        _loaded = true;
      });
    });
  }

  String _shorten(String token) => token.length <= 26
      ? token
      : '${token.substring(0, 12)}…${token.substring(token.length - 10)}';

  Future<void> _copy() async {
    final token = _token;
    if (token == null) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Токен устройства скопирован')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  FaIcon(
                    FontAwesomeIcons.fingerprint,
                    size: 16,
                    color: colors.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Токен устройства',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (!_loaded)
                const LinearProgressIndicator()
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _shorten(_token!),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurface.withValues(alpha: 0.8),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const FaIcon(FontAwesomeIcons.copy, size: 14),
                      tooltip: 'Скопировать',
                      visualDensity: VisualDensity.compact,
                      onPressed: _copy,
                    ),
                  ],
                ),
              Text(
                'Токен привязан к устройству. При ошибочном бане найдите его в '
                'users.device_token_hash (SHA-256) и снимите is_banned.',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
