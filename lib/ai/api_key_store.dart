import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-provider API key storage. The key must never be written to logs, the DB
/// or source code.
abstract interface class AiKeyStore {
  Future<String?> read(String providerId);
  Future<void> write(String providerId, String key);
  Future<void> clear(String providerId);
}

class SecureAiKeyStore implements AiKeyStore {
  SecureAiKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String providerId) => 'lifeos.ai.key.$providerId';

  @override
  Future<String?> read(String providerId) =>
      _storage.read(key: _key(providerId));

  @override
  Future<void> write(String providerId, String key) =>
      _storage.write(key: _key(providerId), value: key);

  @override
  Future<void> clear(String providerId) =>
      _storage.delete(key: _key(providerId));
}

class InMemoryAiKeyStore implements AiKeyStore {
  final Map<String, String> _keys = <String, String>{};

  @override
  Future<String?> read(String providerId) async => _keys[providerId];

  @override
  Future<void> write(String providerId, String key) async {
    _keys[providerId] = key;
  }

  @override
  Future<void> clear(String providerId) async {
    _keys.remove(providerId);
  }
}
