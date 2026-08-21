//lib/screens/widgets/bottom_sheet_widget.dart

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/wifi_point.dart';
import '../../viewmodels/map_viewmodel.dart';
import 'point_feedback_bar.dart';

/// Примерная высота одного тайла списка (используется для скролла к выбранной
/// точке, когда карточка фидбека ещё не построена в виртуализированном списке).
const double _kTileHeight = 72;

class WiFiBottomSheet extends StatefulWidget {
  final DraggableScrollableController controller;
  final WiFiPoint? selectedPoint;
  final Function(WiFiPoint) onPointTap;

  const WiFiBottomSheet({
    super.key,
    required this.controller,
    required this.onPointTap,
    this.selectedPoint,
  });

  @override
  State<WiFiBottomSheet> createState() => _WiFiBottomSheetState();
}

class _WiFiBottomSheetState extends State<WiFiBottomSheet> {
  /// Точка, для которой уже был выполнен скролл/показ карточки.
  WiFiPoint? _lastSelected;

  /// Контроллер списка (передаётся из DraggableScrollableSheet).
  ScrollController? _listController;

  @override
  void didUpdateWidget(WiFiBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPoint != null && widget.selectedPoint != _lastSelected) {
      _lastSelected = widget.selectedPoint;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
    }
  }

  void _scrollToSelected() {
    if (!mounted) return;
    final controller = _listController;
    if (controller == null || !controller.hasClients) return;
    final viewModel = context.read<MapViewModel>();
    final point = widget.selectedPoint;
    if (point == null) return;
    final index = viewModel.points.indexWhere((p) => p == point);
    if (index < 0) return;
    final target = (index * _kTileHeight)
        .clamp(0.0, controller.position.maxScrollExtent);
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DraggableScrollableSheet(
      key: const PageStorageKey<String>('bottom_sheet'),
      controller: widget.controller,
      initialChildSize: 0.3,
      minChildSize: 0.12,
      maxChildSize: 0.85,
      snap: false,
      builder: (context, scrollController) {
        _listController = scrollController;
        return Consumer<MapViewModel>(
          builder: (context, viewModel, _) {
            return GestureDetector(
              onVerticalDragUpdate: (details) {
                final newSize = widget.controller.size -
                    details.primaryDelta! / MediaQuery.of(context).size.height;
                widget.controller.jumpTo(newSize.clamp(0.12, 0.85));
              },
              child: Material(
                elevation: 0,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                color: colors.surface,
                child: Column(
                  children: [
                    _buildSortRow(context, viewModel),
                    Expanded(
                      child: SafeArea(
                        top: false,
                        bottom: true,
                        child: viewModel.points.isEmpty
                            ? _buildEmptyState(context, viewModel)
                            : Scrollbar(
                                controller: scrollController,
                                thumbVisibility: false,
                                thickness: 6,
                                radius: const Radius.circular(12),
                                interactive: true,
                                child: _buildPointList(
                                    context, viewModel, scrollController),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPointList(
      BuildContext context, MapViewModel viewModel, ScrollController controller) {
    final point = widget.selectedPoint;
    final selectedIndex =
        point == null ? -1 : viewModel.points.indexWhere((p) => p == point);

    return ListView.builder(
      padding: EdgeInsets.zero,
      controller: controller,
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
        //color: colors.onSurface.withOpacity(0.05),
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
            viewModel.isFileLoaded ? 'Ничего не найдено' : 'Данные не загружены',
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