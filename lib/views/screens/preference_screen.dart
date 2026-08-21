// lib/views/screens/preferences_screen.dart
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../services/api_client.dart';
import '../../services/server_settings.dart';
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
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 24),
            child: Text(
              'Сервер',
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
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: _ServerSettingsSection(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerSettingsSection extends StatefulWidget {
  const _ServerSettingsSection();

  @override
  State<_ServerSettingsSection> createState() => _ServerSettingsSectionState();
}

class _ServerSettingsSectionState extends State<_ServerSettingsSection> {
  late final TextEditingController _controller;
  String? _statusText;
  bool _isOk = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ServerSettings.baseUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ServerSettings.save(_controller.text);
    if (!mounted) return;
    setState(() {
      _statusText = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Адрес сервера сохранён')),
    );
  }

  Future<void> _testConnection() async {
    await ServerSettings.save(_controller.text);
    setState(() {
      _checking = true;
      _statusText = null;
    });
    try {
      final regions = await ApiClient().fetchRegions();
      if (!mounted) return;
      setState(() {
        _checking = false;
        _isOk = true;
        _statusText = 'Соединение установлено. Регионов: ${regions.length}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _isOk = false;
        _statusText = 'Ошибка соединения: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Адрес сервера',
            hintText: 'http://192.168.1.10:23125',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const FaIcon(FontAwesomeIcons.server, size: 16),
          ),
        ),
        const SizedBox(height: 8),
        if (_statusText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  _isOk ? Icons.check_circle : Icons.error,
                  size: 16,
                  color: _isOk ? Colors.green : colors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _statusText!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _save,
                icon: const FaIcon(FontAwesomeIcons.floppyDisk, size: 14),
                label: const Text('Сохранить'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _checking ? null : _testConnection,
                icon: _checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const FaIcon(FontAwesomeIcons.wifi, size: 14),
                label: const Text('Проверить'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Для реального устройства укажите LAN-IP компьютера, на котором '
          'запущен бэкенд (например http://192.168.1.10:23125). '
          'Эмулятор Android использует http://10.0.2.2:23125.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
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
