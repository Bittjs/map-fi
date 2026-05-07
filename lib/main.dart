// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import 'viewmodels/map_viewmodel.dart';
import 'views/screens/main_screen.dart';
import 'views/screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

    await FMTCObjectBoxBackend().initialise();
    await FMTCStore('mapStore').manage.create();

  // Проверяем, был ли пройден онбординг
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;

  runApp(MapFiApp(showOnboarding: !onboardingDone));
}

class MapFiApp extends StatelessWidget {
  final bool showOnboarding;

  const MapFiApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MapViewModel(),
      child: MaterialApp(
        title: 'MapFi',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color.fromARGB(255, 22, 160, 133),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: Colors.black87,
          ),
        ),
        home: showOnboarding
            ? const OnboardingScreen()
            : const MainScreen(),
      ),
    );
  }
}
