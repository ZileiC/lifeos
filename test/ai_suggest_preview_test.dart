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

String _jsonFor({
  required String taskId,
  required DateTime start,
  required DateTime end,
}) {
  return jsonEncode(<String, dynamic>{
    'answer': '先写报告',
    'plan': [
      {
        'taskId': taskId,
        'startAt': start.toIso8601String(),
        'endAt': end.toIso8601String(),
        'reason': 'deep work',
      }
    ],
    'conflicts': <String>[],
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  AppDatabase db,
  String response,
) async {
  final keyStore = InMemoryAiKeyStore();
  await keyStore.write('deepseek', 'sk-test');
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

  testWidgets('boots with AI stores', (tester) async {
    await _pumpApp(tester, db, '{}');
    expect(find.text('LifeOS'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('AI suggestion previews in the grid and only writes on confirm',
      (tester) async {
    final taskId = await repo.createTask(
      title: '写报告',
      urgency: 8,
      importance: 9,
      estimatedMinutes: 60,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    final start = today.add(const Duration(hours: 9));
    final end = start.add(const Duration(hours: 1));
    await _pumpApp(tester, db, _jsonFor(taskId: taskId, start: start, end: end));

    await tester.tap(find.text('日视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('day-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('day-ai')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('suggested-0')), findsOneWidget);
    expect(find.text('AI 建议'), findsWidgets);
    expect(await repo.fetchSlicesForDay(today), isEmpty);

    await tester.tap(find.byKey(const Key('suggestion-confirm')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final written = await repo.fetchSlicesForDay(today);
    expect(written, hasLength(1));
    expect(written.single.slice.taskId, taskId);

    await _disposeApp(tester);
  });

  testWidgets('ignoring an AI suggestion writes nothing', (tester) async {
    final taskId = await repo.createTask(title: '写报告');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    final start = today.add(const Duration(hours: 9));
    final end = start.add(const Duration(hours: 1));
    await _pumpApp(tester, db, _jsonFor(taskId: taskId, start: start, end: end));

    await tester.tap(find.text('日视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('day-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('day-ai')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('suggested-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('suggestion-ignore')));
    await tester.pumpAndSettle();
    expect(await repo.fetchSlicesForDay(today), isEmpty);

    await _disposeApp(tester);
  });
}
