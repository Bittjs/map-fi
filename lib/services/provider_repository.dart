// lib/services/provider_repository.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MapProviderRepository {
  static const String _keySelectedProvider = 'map_provider';
  static const String _keyApiKeys = 'map_api_key';

  Future<String> getSelectedProviderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySelectedProvider) ?? 'osm';
  }

  Future<void> saveSelectedProviderId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedProvider, id);
  }

  Future<Map<String, String>> getApiKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final keysJson = prefs.getString(_keyApiKeys);
    if (keysJson == null) return {};

    try {
      final decoded = jsonDecode(keysJson) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveApiKeys(Map<String, String> apiKeys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKeys, jsonEncode(apiKeys));
  }
}
