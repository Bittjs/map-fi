import 'package:flutter/material.dart';
import 'package:mapfi/views/screens/main_screen.dart';
import 'package:mapfi/views/screens/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  final bool showOnboarding;

  const SplashScreen({
    super.key,
    required this.showOnboarding,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    Future.delayed(const Duration(milliseconds: 900), () {
      final nextScreen = widget.showOnboarding
          ? const OnboardingScreen()
          : const MainScreen();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => nextScreen),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const double iconSize = 140;
    
    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Фоновый силуэт
                Icon(
                  Icons.wifi_rounded,
                  size: iconSize,
                  color: colors.onSurface.withValues(alpha: 0.18),
                ),

                ClipRect(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: _controller.value,

                    child: Icon(
                      Icons.wifi_rounded,
                      size: iconSize,
                      color: colors.primary,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}