import 'dart:convert';

/// API protocol used by a provider. Stage 1 only implements the
/// OpenAI-compatible chat-completions protocol; DeepSeek itself also exposes
/// that protocol, so it is a preset rather than a special client.
enum AiProtocol { openai }

/// One configured AI provider. The API key is stored separately in the secure
/// key store (never in this config / DB / logs).
class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.model,
  });

  final String id;
  final String name;
  final AiProtocol protocol;
  final String baseUrl;
  final String model;

  AiProviderConfig copyWith({
    String? id,
    String? name,
    AiProtocol? protocol,
    String? baseUrl,
    String? model,
  }) {
    return AiProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'baseUrl': baseUrl,
        'model': model,
      };

  static AiProviderConfig? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final baseUrl = json['baseUrl'];
    final model = json['model'];
    if (id is! String || name is! String || baseUrl is! String || model is! String) {
      return null;
    }
    return AiProviderConfig(
      id: id,
      name: name,
      protocol: AiProtocol.openai,
      baseUrl: baseUrl,
      model: model,
    );
  }

  /// DeepSeek preset. Current official IDs (2026-11):
  /// - `deepseek-flash` (DeepSeek-V4.1-Flash)
  /// - `deepseek-v4-pro` (DeepSeek-V4-Pro)
  static const AiProviderConfig deepSeek = AiProviderConfig(
    id: 'deepseek',
    name: 'DeepSeek',
    protocol: AiProtocol.openai,
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-flash',
  );

  static const List<AiProviderConfig> defaultProviders = <AiProviderConfig>[
    deepSeek,
  ];

  static const List<String> deepSeekModels = <String>[
    'deepseek-flash',
    'deepseek-v4-pro',
  ];
}

/// A model returned by `GET /models` (OpenAI-compatible).
class AiModelInfo {
  const AiModelInfo({
    required this.id,
    this.name,
    this.contextWindow,
    this.maxOutputTokens,
  });

  final String id;
  final String? name;
  final int? contextWindow;
  final int? maxOutputTokens;

  static AiModelInfo? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    return AiModelInfo(
      id: id,
      name: json['name'] is String ? json['name'] as String : null,
      contextWindow: json['context_window'] is int
          ? json['context_window'] as int
          : null,
      maxOutputTokens: json['max_output_tokens'] is int
          ? json['max_output_tokens'] as int
          : null,
    );
  }

  static List<AiModelInfo> parseList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const <AiModelInfo>[];
    final data = decoded['data'];
    if (data is! List) return const <AiModelInfo>[];
    return data
        .whereType<Map<String, dynamic>>()
        .map(AiModelInfo.tryParse)
        .whereType<AiModelInfo>()
        .toList();
  }
}
