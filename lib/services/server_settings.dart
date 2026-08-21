// lib/services/server_settings.dart
// Настройка адреса бэкенда, сохраняется в SharedPreferences.
// Значение читается динамически ApiClient при каждом запросе — смена адреса
// в Предпочтениях работает без пересоздания провайдеров.

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';

class ServerSettings {
  static const _key = 'server_base_url';

  static String _baseUrl = defaultBaseUrl;

  /// Текущий адрес бэкенда.
  static String get baseUrl => _baseUrl;

  /// Адрес по умолчанию: Android-эмулятор → 10.0.2.2 (петля хоста),
  /// остальные платформы → localhost.
  static String get defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:23125';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:23125';
    }
    return 'http://localhost:23125';
  }

  /// Загружает сохранённый адрес (вызывается в main() до runApp).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) {
      _baseUrl = saved;
    }
  }

  /// Сохраняет адрес, нормализуя форму (добавляет http://, убирает слеш).
  static Future<void> save(String url) async {
    var clean = url.trim();
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'http://$clean';
    }
    _baseUrl = clean;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, clean);
  }
}