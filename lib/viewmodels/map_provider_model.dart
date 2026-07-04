import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MapProviderInfo {
  final String id;
  final String name;
  final String subtitle;
  final FaIconData icon;
  final bool requiresKey;
  final String urlTemplate;

  const MapProviderInfo({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.requiresKey,
    required this.urlTemplate,
  });
}

class MapProviderModel extends ChangeNotifier {
  static const String _keySelectedProvider = 'map_provider';
  static const String _keyApiKeys = 'map_api_key';

  static const List<MapProviderInfo> providers = [
    MapProviderInfo(
      id: 'osm',
      name: 'OpenStreetMap',
      subtitle: 'Открытый, надёжный, бесплатный',
      icon: FontAwesomeIcons.map,
      requiresKey: false,
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    ),
    MapProviderInfo(
      id: 'wikimedia',
      name: 'Wikimedia',
      subtitle: 'Альтернативный бесплатный вариант',
      icon: FontAwesomeIcons.globe,
      requiresKey: false,
      urlTemplate: 'https://maps.wikimedia.org/osm-intl/{z}/{x}/{y}.png',
        ),
    MapProviderInfo(
      id: '2gis',
      name: '2GIS',
      subtitle: 'Популярная карта, требуется API-ключ',
      icon: FontAwesomeIcons.compass,
      requiresKey: true,
      urlTemplate: 'https://tile2.maps.2gis.com/tiles?x={x}&y={y}&z={z}&v=1&key={key}',
    ),
  ];

 
  String _selectedProviderId = 'osm';
  Map<String, String> _apiKeys = {}; // id -> ключ
  bool _isInitialized = false;

  String get selectedProviderId => _selectedProviderId;
  Map<String, String> get apiKeys => _apiKeys;
  bool get isInitialized => _isInitialized;

  String get currentApiKey => _apiKeys[_selectedProviderId] ?? '';

  MapProviderInfo get currentProvider {
    final provider = providers.firstWhere(
      (p) => p.id == _selectedProviderId,
      orElse: () => providers.first,
    );
    // Fallback на OSM, если нужен ключ, а его нет
    if (provider.requiresKey && (_apiKeys[provider.id] ?? '').isEmpty) {
      return providers.firstWhere((p) => p.id == 'osm');
    }
    return provider;
  }

  String get currentUrlTemplate {
    final p = currentProvider;
    if (p.requiresKey) {
      return p.urlTemplate.replaceAll('{key}', _apiKeys[p.id] ?? '');
    }
    return p.urlTemplate;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedProviderId = prefs.getString(_keySelectedProvider) ?? 'osm';

    final keysJson = prefs.getString(_keyApiKeys);
    if (keysJson != null) {
      try {
        final decoded = jsonDecode(keysJson) as Map<String, dynamic>;
        _apiKeys = decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {
        _apiKeys = {};
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> selectProvider(String providerId) async {
    final provider = providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => providers.first,
    );
    if (provider.requiresKey && (_apiKeys[providerId] ?? '').isEmpty) {
      return; // нельзя выбрать без ключа
    }
    _selectedProviderId = providerId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedProvider, providerId);
    notifyListeners();
  }

  Future<bool> setApiKey(String providerId, String key) async {
    if (key.trim().isEmpty) return false;
    _apiKeys[providerId] = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKeys, jsonEncode(_apiKeys));

    // Автовыбор после ввода ключа
    _selectedProviderId = providerId;
    await prefs.setString(_keySelectedProvider, providerId);

    notifyListeners();
    return true;
  }

  Future<void> removeApiKey(String providerId) async {
    _apiKeys.remove(providerId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKeys, jsonEncode(_apiKeys));

    if (_selectedProviderId == providerId) {
      _selectedProviderId = 'osm';
      await prefs.setString(_keySelectedProvider, 'osm');
    }
    notifyListeners();
  }
}