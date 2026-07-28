// lib/viewmodels/provider_viewmodel.dart
import 'package:flutter/foundation.dart';

import '../services/provider_repository.dart';

import '../models/provider_model.dart';
export '../models/provider_model.dart';

class MapProviderViewModel extends ChangeNotifier {
  final MapProviderRepository _repository;

  MapProviderViewModel({MapProviderRepository? repository})
      : _repository = repository ?? MapProviderRepository();

  List<MapProviderInfo> get providers => MapProviderInfo.defaultProviders;

  String _selectedProviderId = 'osm';
  Map<String, String> _apiKeys = {};
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
    _selectedProviderId = await _repository.getSelectedProviderId();
    _apiKeys = await _repository.getApiKeys();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> selectProvider(String providerId) async {
    final provider = providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => providers.first,
    );
    if (provider.requiresKey && (_apiKeys[providerId] ?? '').isEmpty) {
      return; // Нельзя выбрать без ключа
    }
    _selectedProviderId = providerId;
    await _repository.saveSelectedProviderId(providerId);
    notifyListeners();
  }

  Future<bool> setApiKey(String providerId, String key) async {
    final trimmedKey = key.trim();
    if (trimmedKey.isEmpty) return false;

    _apiKeys[providerId] = trimmedKey;
    await _repository.saveApiKeys(_apiKeys);

    // Автовыбор после ввода ключа
    _selectedProviderId = providerId;
    await _repository.saveSelectedProviderId(providerId);

    notifyListeners();
    return true;
  }

  Future<void> removeApiKey(String providerId) async {
    _apiKeys.remove(providerId);
    await _repository.saveApiKeys(_apiKeys);

    if (_selectedProviderId == providerId) {
      _selectedProviderId = 'osm';
      await _repository.saveSelectedProviderId('osm');
    }
    notifyListeners();
  }
}
