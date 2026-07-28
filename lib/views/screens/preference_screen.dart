// lib/views/screens/preferences_screen.dart
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/preference_viewmodel.dart';

class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final themeViewModel = context.watch<ThemeViewModel>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const FaIcon(FontAwesomeIcons.arrowLeft, size: 18),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Назад',
        ),
        title: Text(
          'Предпочтения',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Внешний вид',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colors.onSurface.withValues(alpha: 0.12),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.onSurface.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ThemeTile(
                    title: 'Светлая',
                    subtitle: 'Классическое светлое оформление',
                    icon: FontAwesomeIcons.sun,
                    isSelected: themeViewModel.themeMode == ThemeMode.light,
                    onTap: () => themeViewModel.setThemeMode(ThemeMode.light),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: colors.onSurface.withValues(alpha: 0.08),
                  ),
                  _ThemeTile(
                    title: 'Тёмная',
                    subtitle: 'Экономия батареи и комфорт ночью',
                    icon: FontAwesomeIcons.moon,
                    isSelected: themeViewModel.themeMode == ThemeMode.dark,
                    onTap: () => themeViewModel.setThemeMode(ThemeMode.dark),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: colors.onSurface.withValues(alpha: 0.08),
                  ),
                  _ThemeTile(
                    title: 'Системная',
                    subtitle: 'Следовать настройкам устройства',
                    icon: FontAwesomeIcons.circleHalfStroke,
                    isSelected: themeViewModel.themeMode == ThemeMode.system,
                    onTap: () => themeViewModel.setThemeMode(ThemeMode.system),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final FaIconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.15)
                    : colors.onSurface.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: FaIcon(
                  icon,
                  size: 18,
                  color: isSelected ? colors.primary : colors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 15,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              FaIcon(
                FontAwesomeIcons.check,
                size: 16,
                color: colors.primary,
              ),
          ],
        ),
      ),
    );
  }
}
