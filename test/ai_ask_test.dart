import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/ai/ai_client.dart';
import 'package:lifeos/ai/ai_provider.dart';
import 'package:lifeos/ai/api_key_store.dart';
import 'package:lifeos/ai/provider_store.dart';
import 'package:lifeos/data/database.dart';
import 'package:lifeos/data/task_repository.dart';
import 'package:lifeos/main.dart';
import 'package:lifeos/providers.dart';

class _FakeAiClient implements AiClient {
  _FakeAiClient(this.response);

  final String response;

  @override
  Future<AiCompletion> complete({
    required AiProviderConfig provider,
    required String apiKey,
    required List<AiMessage> messages,
    double temperature = 0.3,
    int maxTokens = 1500,
    String? reasoningEffort,
  }) async {
    return AiCompletion(content: response);
  }

  @override
  Future<List<AiModelInfo>> listModels({
    required AiProviderConfig provider,
    required String apiKey,
  }) async =>
      const <AiModelInfo>[];
}

Future<void> _pumpApp(
  WidgetTester tester,
  AppDatabase db, {
  required String response,
  required InMemoryAiKeyStore keyStore,
}) async {
  final providerStore = InMemoryAiProviderStore(activeId: 'deepseek');
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      aiKeyStoreProvider.overrideWithValue(keyStore),
      aiProviderStoreProvider.overrideWithValue(providerStore),
      aiClientProvider.overrideWithValue(_FakeAiClient(response)),
      schedulingSkillProvider.overrideWith((ref) async => 'Test skill v2'),
    ],
    child: const LifeOSApp(),
  ));
  await tester.pumpAndSettle();
}

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  late AppDatabase db;
  late TaskRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TaskRepository(db);
  });

  tearDown(() async => db.close());

  testWidgets('ask AI answers from the data and never writes', (tester) async {
    await repo.createTask(
      title: '写报告',
      urgency: 8,
      importance: 9,
      estimatedMinutes: 60,
    );
    final keyStore = InMemoryAiKeyStore();
    await keyStore.write('deepseek', 'sk-test');
    final response = jsonEncode({
      'answer': '今天来得及，先写报告',
      'plan': <Map<String, dynamic>>[],
      'conflicts': <String>[],
    });

    await _pumpApp(tester, db, response: response, keyStore: keyStore);
    await tester.tap(find.byKey(const Key('ai-ask')));
    await tester.pumpAndSettle();
    expect(find.text('问 AI'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ask-input')), '今天来不来得及？');
    await tester.tap(find.byKey(const Key('ask-send')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('今天来得及'), findsOneWidget);
    final now = DateTime.now();
    expect(
      await repo.fetchSlicesForDay(DateTime(now.year, now.month, now.day)),
      isEmpty,
    );

    await _disposeApp(tester);
  });

  testWidgets('ask without a key shows a hint', (tester) async {
    final keyStore = InMemoryAiKeyStore();
    await _pumpApp(
      tester,
      db,
      response: jsonEncode({'answer': 'x', 'plan': [], 'conflicts': []}),
      keyStore: keyStore,
    );
    await tester.tap(find.byKey(const Key('ai-ask')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ask-input')), '今天有空吗？');
    await tester.tap(find.byKey(const Key('ask-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('API key'), findsOneWidget);
    await _disposeApp(tester);
  });
}
