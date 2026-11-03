import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_provider.dart';

/// Non-secret provider configuration + active provider id. The API key is
/// stored separately in [AiKeyStore].
abstract interface class AiProviderStore {
  Future<List<AiProviderConfig>> readProviders();
  Future<void> writeProviders(List<AiProviderConfig> providers);
  Future<String?> readActiveId();
  Future<void> writeActiveId(String? id);
}

class SecureAiProviderStore implements AiProviderStore {
  SecureAiProviderStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _providersKey = 'lifeos.ai.providers';
  static const String _activeKey = 'lifeos.ai.activeProvider';

  @override
  Future<List<AiProviderConfig>> readProviders() async {
    final raw = await _storage.read(key: _providersKey);
    if (raw == null || raw.isEmpty) {
      return AiProviderConfig.defaultProviders;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return AiProviderConfig.defaultProviders;
      final providers = decoded
          .whereType<Map<String, dynamic>>()
          .map(AiProviderConfig.tryParse)
          .whereType<AiProviderConfig>()
          .toList();
      return providers.isEmpty
          ? AiProviderConfig.defaultProviders
          : providers;
    } catch (_) {
      return AiProviderConfig.defaultProviders;
    }
  }

  @override
  Future<void> writeProviders(List<AiProviderConfig> providers) {
    return _storage.write(
      key: _providersKey,
      value: jsonEncode(providers.map((provider) => provider.toJson()).toList()),
    );
  }

  @override
  Future<String?> readActiveId() => _storage.read(key: _activeKey);

  @override
  Future<void> writeActiveId(String? id) {
    if (id == null) return _storage.delete(key: _activeKey);
    return _storage.write(key: _activeKey, value: id);
  }
}

class InMemoryAiProviderStore implements AiProviderStore {
  InMemoryAiProviderStore({List<AiProviderConfig>? providers, this.activeId})
      : _providers = providers ?? AiProviderConfig.defaultProviders;

  List<AiProviderConfig> _providers;
  String? activeId;

  @override
  Future<List<AiProviderConfig>> readProviders() async =>
      List<AiProviderConfig>.of(_providers);

  @override
  Future<void> writeProviders(List<AiProviderConfig> providers) async {
    _providers = List<AiProviderConfig>.of(providers);
  }

  @override
  Future<String?> readActiveId() async => activeId;

  @override
  Future<void> writeActiveId(String? id) async {
    activeId = id;
  }
}
