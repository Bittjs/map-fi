//lib/screens/widgets/bottom_sheet_widget.dart

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/wifi_point.dart';
import '../../viewmodels/map_viewmodel.dart';

class WiFiBottomSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DraggableScrollableSheet(
      key: const PageStorageKey<String>('bottom_sheet'),
      controller: controller,
      initialChildSize: 0.3,
      minChildSize: 0.12,
      maxChildSize: 0.85,
      snap: false,
      builder: (context, scrollController) {
        return Consumer<MapViewModel>(
          builder: (context, viewModel, _) {
            return GestureDetector(
              onVerticalDragUpdate: (details) {
                final newSize = controller.size -
                    details.primaryDelta! / MediaQuery.of(context).size.height;
                controller.jumpTo(newSize.clamp(0.12, 0.85));
              },
              child: Material(
                elevation: 0,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
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
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  controller: scrollController,
                                  itemCount: viewModel.points.length,
                                  itemBuilder: (context, index) {
                                    final point = viewModel.points[index];
                                    return _buildPointTile(context, point, viewModel);
                                  },
                                ),
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
                DropdownMenuItem(value: SortType.nameTop, child: Text('от А до Я')),
                DropdownMenuItem(value: SortType.nameBottom, child: Text('от Я до A')),
                DropdownMenuItem(value: SortType.ratingTop, child: Text('Сначала Лучшие')),
                DropdownMenuItem(value: SortType.ratingBottom, child: Text('Сначала Худшие')),
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

  Widget _buildPointTile(BuildContext context, WiFiPoint point, MapViewModel viewModel) {
    final isSelected = point == selectedPoint;
    final theme = Theme.of(context);

    return ListTile(
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : theme.colorScheme.primary.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(
          point.password.isEmpty ? Icons.wifi_tethering_rounded : Icons.wifi_rounded,
          color: isSelected ? theme.colorScheme.surface : theme.colorScheme.primary,
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
      trailing: PopupMenuButton<String>(
        icon: const FaIcon(FontAwesomeIcons.chevronRight, size: 20),
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'verify',
            child: Text('Верифицировать'),
          ),
        ],
        onSelected: (value) async {
          if (value == 'verify') {
            final ok = await viewModel.verifyPoint(point);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ok
                    ? 'Вы подключены к ${point.name} - точка верифицирована!'
                    : 'Не удалось верифицировать: проверьте SSID и расстояние до точки.'),
              ),
            );
          }
        },
      ),
      onTap: () => onPointTap(point),
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