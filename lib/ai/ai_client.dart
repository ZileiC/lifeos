import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_provider.dart';

class AiMessage {
  const AiMessage({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role,
        'content': content,
      };
}

class AiCompletion {
  const AiCompletion({
    required this.content,
    this.promptTokens,
    this.completionTokens,
  });

  final String content;
  final int? promptTokens;
  final int? completionTokens;
}

class AiApiException implements Exception {
  const AiApiException({
    required this.message,
    this.statusCode,
    this.retryable = false,
  });

  final String message;
  final int? statusCode;
  final bool retryable;

  @override
  String toString() =>
      'AiApiException($statusCode): $message${retryable ? ' [retryable]' : ''}';
}

abstract interface class AiClient {
  Future<AiCompletion> complete({
    required AiProviderConfig provider,
    required String apiKey,
    required List<AiMessage> messages,
    double temperature = 0.3,
    int maxTokens = 1500,
    String? reasoningEffort,
  });

  Future<List<AiModelInfo>> listModels({
    required AiProviderConfig provider,
    required String apiKey,
  });
}

/// OpenAI-compatible `/chat/completions` client. DeepSeek is a preset of this
/// client; any custom OpenAI-compatible provider can be used by changing the
/// base URL / model / key.
class OpenAiCompatibleClient implements AiClient {
  OpenAiCompatibleClient(
    this._http, {
    this.timeout = const Duration(seconds: 30),
  });

  final http.Client _http;
  final Duration timeout;

  @override
  Future<AiCompletion> complete({
    required AiProviderConfig provider,
    required String apiKey,
    required List<AiMessage> messages,
    double temperature = 0.3,
    int maxTokens = 1500,
    String? reasoningEffort,
  }) async {
    final uri = _endpoint(provider.baseUrl, 'chat/completions');
    final body = <String, dynamic>{
      'model': provider.model,
      'messages': messages.map((message) => message.toJson()).toList(),
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': false,
      'response_format': const <String, String>{'type': 'json_object'},
    };
    if (reasoningEffort != null) {
      body['reasoning_effort'] = reasoningEffort;
    }

    final response = await _send(
      () => _http.post(uri, headers: _headers(apiKey), body: jsonEncode(body)),
    );
    final decoded = _decodeJson(response.body);
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiApiException(message: '响应里没有 choices');
    }
    final first = choices.first;
    final message = first is Map<String, dynamic> ? first['message'] : null;
    final content = message is Map<String, dynamic> ? message['content'] : null;
    if (content is! String) {
      throw const AiApiException(message: '响应里没有文本内容');
    }
    final usage = decoded['usage'];
    return AiCompletion(
      content: content,
      promptTokens: usage is Map<String, dynamic> && usage['prompt_tokens'] is int
          ? usage['prompt_tokens'] as int
          : null,
      completionTokens:
          usage is Map<String, dynamic> && usage['completion_tokens'] is int
              ? usage['completion_tokens'] as int
              : null,
    );
  }

  @override
  Future<List<AiModelInfo>> listModels({
    required AiProviderConfig provider,
    required String apiKey,
  }) async {
    final uri = _endpoint(provider.baseUrl, 'models');
    final response = await _send(
      () => _http.get(uri, headers: _headers(apiKey)),
    );
    return AiModelInfo.parseList(response.body);
  }

  Map<String, String> _headers(String apiKey) => <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Uri _endpoint(String baseUrl, String path) {
    final base = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base/$path');
  }

  /// One retry for transient failures (timeout / network / 5xx). 401/429 never
  /// retry; the user must fix the key or billing.
  Future<http.Response> _send(Future<http.Response> Function() request) async {
    AiApiException? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await request().timeout(timeout);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        final error = AiApiException(
          message: _errorMessage(response),
          statusCode: response.statusCode,
          retryable: response.statusCode >= 500,
        );
        if (!error.retryable) throw error;
        lastError = error;
      } on TimeoutException {
        lastError = const AiApiException(message: '请求超时，请检查网络', retryable: true);
      } on http.ClientException catch (error) {
        lastError = AiApiException(message: '网络错误：${error.message}', retryable: true);
      }
      if (attempt == 0) continue;
    }
    throw lastError ?? const AiApiException(message: '请求失败');
  }

  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic> && error['message'] is String) {
          return 'HTTP ${response.statusCode}: ${error['message']}';
        }
        if (decoded['message'] is String) {
          return 'HTTP ${response.statusCode}: ${decoded['message']}';
        }
      }
    } catch (_) {
      // Fall through to the generic message.
    }
    return 'HTTP ${response.statusCode}: ${response.reasonPhrase ?? '请求失败'}';
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through.
    }
    throw const AiApiException(message: '响应不是合法 JSON');
  }
}
