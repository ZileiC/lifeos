import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/ai/ai_provider.dart';
import 'package:lifeos/ai/api_key_store.dart';
import 'package:lifeos/ai/provider_store.dart';

void main() {
  test('in-memory key store saves, reads and clears per provider', () async {
    final store = InMemoryAiKeyStore();
    expect(await store.read('deepseek'), isNull);
    await store.write('deepseek', 'sk-1');
    await store.write('custom', 'sk-2');
    expect(await store.read('deepseek'), 'sk-1');
    expect(await store.read('custom'), 'sk-2');
    await store.clear('deepseek');
    expect(await store.read('deepseek'), isNull);
    expect(await store.read('custom'), 'sk-2');
  });

  test('in-memory provider store defaults to DeepSeek and tracks active', () async {
    final store = InMemoryAiProviderStore();
    final providers = await store.readProviders();
    expect(providers, hasLength(1));
    expect(providers.first.id, 'deepseek');
    expect(await store.readActiveId(), isNull);

    final custom = AiProviderConfig.deepSeek.copyWith(
      id: 'custom',
      name: 'Custom',
      baseUrl: 'https://example.com/v1',
      model: 'my-model',
    );
    await store.writeProviders([AiProviderConfig.deepSeek, custom]);
    await store.writeActiveId('custom');

    expect((await store.readProviders()).map((p) => p.id), [
      'deepseek',
      'custom',
    ]);
    expect(await store.readActiveId(), 'custom');
  });
}
