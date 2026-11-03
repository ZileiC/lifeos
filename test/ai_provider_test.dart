import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/ai/ai_provider.dart';

void main() {
  test('DeepSeek preset uses current official model ids', () {
    expect(AiProviderConfig.deepSeek.baseUrl, 'https://api.deepseek.com');
    expect(AiProviderConfig.deepSeek.model, 'deepseek-flash');
    expect(
      AiProviderConfig.deepSeekModels,
      containsAll(<String>['deepseek-flash', 'deepseek-v4-pro']),
    );
  });

  test('provider config json roundtrip and custom provider', () {
    final custom = AiProviderConfig.deepSeek.copyWith(
      id: 'custom',
      name: 'Custom',
      baseUrl: 'https://example.com/v1',
      model: 'my-model',
    );
    final parsed = AiProviderConfig.tryParse(custom.toJson());
    expect(parsed, isNotNull);
    expect(parsed!.baseUrl, 'https://example.com/v1');
    expect(parsed.model, 'my-model');
  });

  test('model list parse keeps current DeepSeek models and metadata', () {
    final body = jsonEncode(<String, dynamic>{
      'object': 'list',
      'data': <Map<String, dynamic>>[
        {
          'id': 'deepseek-flash',
          'name': 'DeepSeek-V4.1-Flash',
          'context_window': 1048576,
          'max_output_tokens': 393216,
        },
        {
          'id': 'deepseek-v4-pro',
          'name': 'DeepSeek-V4-Pro',
        },
      ],
    });
    final models = AiModelInfo.parseList(body);
    expect(models.map((model) => model.id), <String>[
      'deepseek-flash',
      'deepseek-v4-pro',
    ]);
    expect(models.first.contextWindow, 1048576);
    expect(models.first.maxOutputTokens, 393216);
  });
}
