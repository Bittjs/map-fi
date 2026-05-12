// lib/main.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mapfi/views/screens/splash_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import 'viewmodels/map_viewmodel.dart';
import './app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

    if (!kIsWeb) {
    await FMTCObjectBoxBackend().initialise();
    await const FMTCStore('mapStore').manage.create();
    } else {
    debugPrint('Запуск в Web - FMTC отключен');
    }
    
  // Проверка онбординга
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;

  runApp(MapFiApp(showOnboarding: !onboardingDone));
}

class MapFiApp extends StatelessWidget {
  final bool showOnboarding;

  const MapFiApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    final colorScheme = AppTheme.lightScheme();

    return ChangeNotifierProvider(
      create: (_) => MapViewModel(),
      child: MaterialApp(
        title: 'MapFi',
        debugShowCheckedModeBanner: false,
        
        theme: AppTheme.build(colorScheme),
        
         home: SplashScreen(showOnboarding: showOnboarding)
      ),
    );
  }
}
