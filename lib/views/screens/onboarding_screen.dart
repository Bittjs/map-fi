// lib/views/screens/onboarding_screen.dart
// Экран приветствия — показывается только при первом запуске.
// Разбит на модульные виджеты: логотип, описание, селектор региона,
// статус загрузки, основное действие и пропуск.

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../viewmodels/map_viewmodel.dart';
import 'main_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _isDownloading = false;
  String? _statusMessage;

  Future<void> _downloadRegionData() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'Загрузка данных с сервера…';
    });

    final viewModel = context.read<MapViewModel>();
    final count = await viewModel.synchronizeRegion(viewModel.selectedRegionId);

    if (!mounted) return;

    setState(() {
      _statusMessage = (count != null)
          ? 'Синхронизация завершена! Изменений: $count'
          : 'Ошибка: ${viewModel.lastError ?? 'Сервер недоступен'}';
      _isDownloading = false;
    });
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              const _OnboardingLogo(),
              const SizedBox(height: 24),
              const _WelcomeTitle(),
              const SizedBox(height: 12),
              const _WelcomeDescription(),
              const SizedBox(height: 20),
              Consumer<MapViewModel>(
                builder: (context, viewModel, _) =>
                    _RegionSelector(viewModel: viewModel),
              ),
              const Spacer(),
              if (_statusMessage != null) ...[
                _StatusMessage(
                  message: _statusMessage!,
                  isError: _statusMessage!.startsWith('Ошибка'),
                ),
                const SizedBox(height: 12),
              ],
              _PrimaryAction(
                isDownloading: _isDownloading,
                onPressed: _downloadRegionData,
              ),
              const SizedBox(height: 12),
              _SkipAction(
                isDownloading: _isDownloading,
                onPressed: _finish,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingLogo extends StatelessWidget {
  const _OnboardingLogo();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.wifi_find_rounded, color: Colors.white, size: 56),
    );
  }
}

class _WelcomeTitle extends StatelessWidget {
  const _WelcomeTitle();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Добро пожаловать в MapFi',
      style: Theme.of(context)
          .textTheme
          .headlineSmall
          ?.copyWith(fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
    );
  }
}

class _WelcomeDescription extends StatelessWidget {
  const _WelcomeDescription();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Офлайн-карта точек Wi-Fi. Импортируйте базу из файла '
      'или загрузите данные выбранного региона с сервера.',
      textAlign: TextAlign.center,
    );
  }
}

class _RegionSelector extends StatelessWidget {
  final MapViewModel viewModel;

  const _RegionSelector({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            FontAwesomeIcons.mapLocationDot,
            size: 14,
            color: colors.onSurface.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: viewModel.regions.any((r) => r.id == viewModel.selectedRegionId)
                ? viewModel.selectedRegionId
                : null,
            underline: const SizedBox(),
            isDense: true,
            borderRadius: BorderRadius.circular(16),
            dropdownColor: colors.surface,
            items: viewModel.regions
                .map((r) => DropdownMenuItem(value: r.id, child: Text(r.name)))
                .toList(),
            onChanged: (regionId) {
              if (regionId != null) viewModel.setSelectedRegionId(regionId);
            },
          ),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  final String message;
  final bool isError;

  const _StatusMessage({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(color: isError ? colors.error : colors.primary),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  final bool isDownloading;
  final VoidCallback onPressed;

  const _PrimaryAction({required this.isDownloading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isDownloading ? null : onPressed,
        icon: isDownloading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: colors.surface),
              )
            : const FaIcon(FontAwesomeIcons.cloudArrowDown),
        label: const Text('Загрузить данные региона'),
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class _SkipAction extends StatelessWidget {
  final bool isDownloading;
  final VoidCallback onPressed;

  const _SkipAction({required this.isDownloading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isDownloading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text('Продолжить'),
      ),
    );
  }
}