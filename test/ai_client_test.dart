import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifeos/ai/ai_client.dart';
import 'package:lifeos/ai/ai_provider.dart';

void main() {
  test('complete sends OpenAI-compatible request and parses content', () async {
    late http.Request captured;
    final client = OpenAiCompatibleClient(MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'choices': [
            {
              'message': {'content': '{"answer":"ok"}'},
            }
          ],
          'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
        }),
        200,
      );
    }));

    final completion = await client.complete(
      provider: AiProviderConfig.deepSeek,
      apiKey: 'sk-test',
      messages: const [AiMessage(role: 'user', content: 'hi')],
    );

    expect(completion.content, '{"answer":"ok"}');
    expect(completion.promptTokens, 10);
    expect(completion.completionTokens, 5);
    expect(
      captured.url.toString(),
      'https://api.deepseek.com/chat/completions',
    );
    expect(captured.headers['Authorization'], 'Bearer sk-test');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'deepseek-flash');
    expect(body['messages'], [
      {'role': 'user', 'content': 'hi'}
    ]);
    expect(body['response_format'], {'type': 'json_object'});
  });

  test('custom provider uses its own base URL and model', () async {
    late http.Request captured;
    final client = OpenAiCompatibleClient(MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{}'},
            }
          ],
        }),
        200,
      );
    }));
    final custom = AiProviderConfig.deepSeek.copyWith(
      id: 'custom',
      name: 'Custom',
      baseUrl: 'https://example.com/v1/',
      model: 'my-model',
    );

    await client.complete(
      provider: custom,
      apiKey: 'k',
      messages: const [AiMessage(role: 'user', content: 'x')],
    );

    expect(captured.url.toString(), 'https://example.com/v1/chat/completions');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'my-model');
  });

  test('401 is not retried and throws a clear error', () async {
    var calls = 0;
    final client = OpenAiCompatibleClient(MockClient((request) async {
      calls++;
      return http.Response('{"error":{"message":"bad key"}}', 401);
    }));

    await expectLater(
      client.complete(
        provider: AiProviderConfig.deepSeek,
        apiKey: 'bad',
        messages: const [AiMessage(role: 'user', content: 'x')],
      ),
      throwsA(isA<AiApiException>()
          .having((error) => error.statusCode, 'status', 401)
          .having((error) => error.message, 'message', contains('bad key'))),
    );
    expect(calls, 1);
  });

  test('500 is retried once', () async {
    var calls = 0;
    final client = OpenAiCompatibleClient(MockClient((request) async {
      calls++;
      if (calls == 1) return http.Response('{}', 500);
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '{}'},
            }
          ],
        }),
        200,
      );
    }));

    final completion = await client.complete(
      provider: AiProviderConfig.deepSeek,
      apiKey: 'k',
      messages: const [AiMessage(role: 'user', content: 'x')],
    );
    expect(completion.content, '{}');
    expect(calls, 2);
  });

  test('timeout throws a retryable AiApiException', () async {
    final client = OpenAiCompatibleClient(
      MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response('{}', 200);
      }),
      timeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      client.complete(
        provider: AiProviderConfig.deepSeek,
        apiKey: 'k',
        messages: const [AiMessage(role: 'user', content: 'x')],
      ),
      throwsA(isA<AiApiException>()
          .having((error) => error.retryable, 'retryable', isTrue)),
    );
  });

  test('listModels parses /models response', () async {
    final client = OpenAiCompatibleClient(MockClient((request) async {
      expect(request.url.toString(), 'https://api.deepseek.com/models');
      return http.Response(
        jsonEncode({
          'object': 'list',
          'data': [
            {'id': 'deepseek-flash', 'name': 'DeepSeek-V4.1-Flash'},
            {'id': 'deepseek-v4-pro', 'name': 'DeepSeek-V4-Pro'},
          ],
        }),
        200,
      );
    }));

    final models = await client.listModels(
      provider: AiProviderConfig.deepSeek,
      apiKey: 'k',
    );
    expect(models.map((model) => model.id), [
      'deepseek-flash',
      'deepseek-v4-pro',
    ]);
  });
}
