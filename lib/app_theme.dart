// lib/app_theme.dart
//Полу-рабочая единая тема для всего приложения
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ColorScheme lightScheme() => const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF16A085),
        onPrimary: Colors.white,
        secondary: Color(0xFFFFC20A),
        onSecondary: Colors.black,
        error: Color(0xFFe80049),
        onError: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
      );

  static ColorScheme darkScheme() => const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFF1ABC9C),
        onPrimary: Colors.black,
        secondary: Color(0xFFFFD54F),
        onSecondary: Colors.black,
        error: Color(0xFFFF5252),
        onError: Colors.black,
        surface: Color(0xFF121212),
        onSurface: Colors.white,
      );

  //Метод сборщик
  static ThemeData build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,

      textTheme: GoogleFonts.openSansTextTheme(
          // Обязательно передаем базовый textTheme,
          // чтобы цвет шрифтов адаптировался под scheme.onSurface
          ThemeData(brightness: scheme.brightness).textTheme),

      // Цвет фона экранов (Scaffold) по умолчанию
      scaffoldBackgroundColor: scheme.surface,

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: scheme.onSurface,
        centerTitle: true,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        titleTextStyle: TextStyle(
            color: scheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(
            color: scheme.onSurface.withValues(alpha: 0.8), fontSize: 16),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(scheme.surface),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: scheme.onSurface.withValues(alpha: 0.12), width: 1),
            ),
          ),
          elevation: WidgetStateProperty.all(8),
        ),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface.withValues(alpha: 0.5),
        elevation: 2,
      ),
    );
  }
}
