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
    const double iconSize = 180;

    return Scaffold(
      backgroundColor: Colors.white,
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
                  color: Colors.grey.withOpacity(0.18),
                ),

                // Анимированное заполнение
                ClipRect(
                  child: Align(
                    alignment: Alignment.bottomCenter,

                    heightFactor: _controller.value,

                    child: const Icon(
                      Icons.wifi_rounded,
                      size: iconSize,
                      color: Color(0xFF16A085),
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