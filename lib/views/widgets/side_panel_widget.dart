//lib/screens/widgets/side_panel_widget.dart

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/wifi_point.dart';
import '../../viewmodels/map_viewmodel.dart';
import 'point_feedback_bar.dart';

/// Примерная высота одного тайла списка (используется для скролла к выбранной
/// точке, когда карточка фидбека ещё не построена в виртуализированном списке).
const double _kTileHeight = 72;

class WiFiSidePanel extends StatefulWidget {
  final WiFiPoint? selectedPoint;
  final Function(WiFiPoint) onPointTap;

  const WiFiSidePanel({
    super.key,
    required this.onPointTap,
    this.selectedPoint,
  });

  @override
  State<WiFiSidePanel> createState() => _WiFiSidePanelState();
}

class _WiFiSidePanelState extends State<WiFiSidePanel> {
  final ScrollController _scrollController = ScrollController();

  /// Точка, для которой уже был выполнен скролл/показ карточки.
  WiFiPoint? _lastSelected;

  @override
  void didUpdateWidget(WiFiSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPoint != null && widget.selectedPoint != _lastSelected) {
      _lastSelected = widget.selectedPoint;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    if (!mounted || !_scrollController.hasClients) return;
    final viewModel = context.read<MapViewModel>();
    final point = widget.selectedPoint;
    if (point == null) return;
    final index = viewModel.points.indexWhere((p) => p == point);
    if (index < 0) return;
    final target =
        (index * _kTileHeight).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Consumer<MapViewModel>(
      builder: (context, viewModel, _) {
        return Material(
          elevation: 4,
          color: colors.surface,
          child: Column(
            children: [
              _buildSortRow(context, viewModel),

              // Основной список точек или пустой экран
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: true,
                  child: viewModel.points.isEmpty
                      ? _buildEmptyState(context, viewModel)
                      : Scrollbar(
                          interactive: true,
                          controller: _scrollController,
                          thickness: 6,
                          radius: const Radius.circular(12),
                          child: _buildPointList(context, viewModel),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPointList(BuildContext context, MapViewModel viewModel) {
    final point = widget.selectedPoint;
    final selectedIndex =
        point == null ? -1 : viewModel.points.indexWhere((p) => p == point);

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: viewModel.points.length + (selectedIndex >= 0 ? 1 : 0),
      itemBuilder: (context, index) {
        if (selectedIndex >= 0 && index == selectedIndex + 1) {
          return PointFeedbackBar(
            key: ValueKey('feedback_${point!.id}'),
            point: point,
            viewModel: viewModel,
          );
        }
        final pointIndex = (selectedIndex >= 0 && index > selectedIndex)
            ? index - 1
            : index;
        final item = viewModel.points[pointIndex];
        return _buildPointTile(context, item, viewModel);
      },
    );
  }

  Widget _buildSortRow(BuildContext context, MapViewModel viewModel) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurface.withValues(alpha: 0.9),
      fontWeight: FontWeight.w500,
      fontSize: 14,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Text(
            'Точек: ${viewModel.points.length}',
            style: textStyle?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.onSurface.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<SortType>(
              value: viewModel.currentSort,
              underline: const SizedBox(),
              isDense: true,
              borderRadius: BorderRadius.circular(16),
              dropdownColor: colors.surface,
              iconEnabledColor: colors.onSurface.withValues(alpha: 0.8),
              style: textStyle?.copyWith(fontWeight: FontWeight.w600),
              icon: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: FaIcon(FontAwesomeIcons.sort, size: 12),
              ),
              items: const [
                DropdownMenuItem(
                    value: SortType.nameTop, child: Text('от А до Я')),
                DropdownMenuItem(
                    value: SortType.nameBottom, child: Text('от Я до A')),
                DropdownMenuItem(
                    value: SortType.ratingTop, child: Text('Сначала Лучшие')),
                DropdownMenuItem(
                    value: SortType.ratingBottom,
                    child: Text('Сначала Худшие')),
              ],
              onChanged: (value) {
                if (value != null) viewModel.changeSort(value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointTile(
      BuildContext context, WiFiPoint point, MapViewModel viewModel) {
    final isSelected = point == widget.selectedPoint;
    final theme = Theme.of(context);

    return ListTile(
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.primary.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(
          point.password.isEmpty
              ? Icons.wifi_tethering_rounded
              : Icons.wifi_rounded,
          color: isSelected
              ? theme.colorScheme.surface
              : theme.colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        point.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        point.password.isEmpty ? 'Публичная' : 'Пароль: ${point.password}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: FaIcon(
        FontAwesomeIcons.chevronRight,
        size: 18,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      onTap: () => widget.onPointTap(point),
    );
  }

  Widget _buildEmptyState(BuildContext context, MapViewModel viewModel) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            viewModel.isFileLoaded
                ? 'Ничего не найдено'
                : 'Данные не загружены',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (!viewModel.isFileLoaded)
            TextButton.icon(
              icon: const FaIcon(FontAwesomeIcons.file),
              label: const Text('Импортировать файл'),
              onPressed: viewModel.pickAndLoadDatabase,
            ),
        ],
      ),
    );
  }
}