// lib/views/screens/onboarding_screen.dart

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../viewmodels/map_viewmodel.dart';
import '../../services/sync_service.dart';
import 'main_screen.dart';

/// Экран приветствия — показывается только при первом запуске.
/// Предлагает загрузить демонстрационную базу с GitHub.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _demoUrl =
      'https://raw.githubusercontent.com/bittjs/mapfi-data/main/points.json';

  bool _isDownloading = false;
  String? _statusMessage;

  // ---------------------------------------------------------------------------

  Future<void> _downloadDemo() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'Загрузка демонстрационной базы…';
    });

    final viewModel = context.read<MapViewModel>();
    await viewModel.syncService.setSyncUrl(_demoUrl);
    final result = await viewModel.synchronize();

    if (!mounted) return;

    switch (result.status) {
      case SyncStatus.newDataAvailable:
        await viewModel.applySyncResult(result);
        setState(() => _statusMessage = 'База загружена! Точек: ${result.points.length}');
      case SyncStatus.notModified:
        setState(() => _statusMessage = 'База уже актуальна.');
      case SyncStatus.error:
        setState(() => _statusMessage = 'Ошибка: ${result.errorMessage}');
    }

    setState(() => _isDownloading = false);
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  // ---------------------------------------------------------------------------

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

              // Логотип / иконка
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_find_rounded, color: Colors.white, size: 56),
              ),

              const SizedBox(height: 24),

              Text(
                'Добро пожаловать в MapFi',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              Text(
                'Офлайн-карта точек Wi-Fi. Импортируйте базу из файла '
                'или загрузите демонстрационные данные прямо сейчас.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.black54),
                textAlign: TextAlign.center,
              ),

              const Spacer(),

              // Статус загрузки
              if (_statusMessage != null) ...[
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _statusMessage!.startsWith('Ошибка')
                        ? Colors.red
                        : Colors.green.shade700,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Кнопка: загрузить демо
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _downloadDemo,
                  icon: _isDownloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const FaIcon(FontAwesomeIcons.cloudArrowDown),
                  label: const Text('Загрузить демонстрационную базу'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 22, 160, 133),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Кнопка: пропустить
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isDownloading ? null : _finish,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Начать без базы'),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
