import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/ai/ai_client.dart';
import 'package:lifeos/ai/ai_provider.dart';
import 'package:lifeos/ai/api_key_store.dart';
import 'package:lifeos/ai/provider_store.dart';
import 'package:lifeos/data/database.dart';
import 'package:lifeos/data/recurrence.dart';
import 'package:lifeos/data/task_repository.dart';
import 'package:lifeos/main.dart';
import 'package:lifeos/providers.dart';

Widget _app(AppDatabase db) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const LifeOSApp(),
  );
}

class _FakeAiClient implements AiClient {
  @override
  Future<AiCompletion> complete({
    required AiProviderConfig provider,
    required String apiKey,
    required List<AiMessage> messages,
    double temperature = 0.3,
    int maxTokens = 1500,
    String? reasoningEffort,
  }) async {
    return const AiCompletion(content: '{}');
  }

  @override
  Future<List<AiModelInfo>> listModels({
    required AiProviderConfig provider,
    required String apiKey,
  }) async {
    return const [
      AiModelInfo(id: 'deepseek-flash', name: 'DeepSeek-V4.1-Flash'),
      AiModelInfo(id: 'deepseek-v4-pro', name: 'DeepSeek-V4-Pro'),
    ];
  }
}

/// Disposes the ProviderScope and drains Drift's zero-duration stream-store
/// timers before flutter_test's pending-timer invariant runs.
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

  testWidgets('capture a task with exact 1-10 U&I', (tester) async {
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-title')), '写报告');
    await tester.ensureVisible(find.byKey(const Key('urgency-7')));
    await tester.tap(find.byKey(const Key('urgency-7')));
    await tester.ensureVisible(find.byKey(const Key('importance-9')));
    await tester.tap(find.byKey(const Key('importance-9')));
    await tester.ensureVisible(find.byKey(const Key('task-estimate')));
    await tester.enterText(find.byKey(const Key('task-estimate')), '120');
    await tester.tap(find.byKey(const Key('task-save')));
    await tester.pumpAndSettle();

    expect(find.text('写报告'), findsOneWidget);
    expect(find.textContaining('U7'), findsOneWidget);
    expect(find.textContaining('I9'), findsOneWidget);
    expect(find.textContaining('通知权限'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('完成'), findsNothing);
    await _disposeApp(tester);
  });

  testWidgets('U&I accepts the edges 1 and 10', (tester) async {
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-title')), '边缘');
    await tester.ensureVisible(find.byKey(const Key('urgency-1')));
    await tester.tap(find.byKey(const Key('urgency-1')));
    await tester.ensureVisible(find.byKey(const Key('importance-10')));
    await tester.tap(find.byKey(const Key('importance-10')));
    await tester.ensureVisible(find.byKey(const Key('task-estimate')));
    await tester.enterText(find.byKey(const Key('task-estimate')), '30');
    await tester.tap(find.byKey(const Key('task-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('U1'), findsOneWidget);
    expect(find.textContaining('I10'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('plan a slice from detail and show it in day view', (tester) async {
    await repo.createTask(title: '写报告', estimatedMinutes: 60);
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('写报告'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail-plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('slice-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    await tester.tap(find.text('日视图'));
    await tester.pumpAndSettle();
    expect(find.text('写报告'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('note is only visible in task detail', (tester) async {
    await repo.createTask(title: 'A', note: '秘密备注', estimatedMinutes: 30);
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    expect(find.text('秘密备注'), findsNothing);
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(find.text('秘密备注'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('create weekly-fixed task generates same-color slices',
      (tester) async {
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-title')), '课');
    await tester.tap(find.text('每周固定'));
    await tester.pumpAndSettle();

    final day = DateTime.now().weekday == 1 ? 3 : 1;
    await tester.ensureVisible(find.byKey(Key('weekday-$day')));
    await tester.tap(find.byKey(Key('weekday-$day')));
    await tester.tap(find.byKey(const Key('task-save')));
    await tester.pumpAndSettle();

    final task = await db.select(db.records).getSingle();
    final spec = RecurrenceSpec.tryParse(task.recurrence);
    expect(spec, isNotNull);
    expect(spec!.weekdays.contains(day), isTrue);
    final slices = await db.select(db.daySlices).get();
    expect(slices, isNotEmpty);
    expect(slices.every((slice) => slice.taskId == task.id), isTrue);
    expect(
      slices.every((slice) =>
          slice.taskId == task.id &&
          task.color != null),
      isTrue,
    );
    expect(find.textContaining('每周'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('editing weekly template keeps existing slices', (tester) async {
    final spec = RecurrenceSpec(
      weekdays: {1},
      startMinutes: 9 * 60,
      durationMinutes: 60,
      fromDate: DateTime(2026, 11, 2),
      toDate: DateTime(2026, 11, 30),
    );
    final id = await repo.createTask(title: '课', recurrence: spec);
    final before = await db.select(db.daySlices).get();
    expect(before, hasLength(5));

    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-title')), '新课');
    await tester.tap(find.byKey(const Key('task-save')));
    await tester.pumpAndSettle();

    final after = await db.select(db.daySlices).get();
    expect(after, hasLength(before.length));
    final task = await (db.select(db.records)
          ..where((r) => r.id.equals(id)))
        .getSingle();
    expect(task.title, '新课');
    await _disposeApp(tester);
  });

  testWidgets('batch move to day and single-step undo', (tester) async {
    final id = await repo.createTask(
      title: 'A',
      dueAt: DateTime(2026, 11, 10, 14, 30),
      dueHasTime: true,
      estimatedMinutes: 60,
    );
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('batch-move')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已移到'), findsOneWidget);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final moved = await (db.select(db.records)
          ..where((r) => r.id.equals(id)))
        .getSingle();
    expect(moved.dueAt, DateTime(today.year, today.month, today.day, 14, 30));

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    final restored = await (db.select(db.records)
          ..where((r) => r.id.equals(id)))
        .getSingle();
    expect(restored.dueAt, DateTime(2026, 11, 10, 14, 30));
    await _disposeApp(tester);
  });

  testWidgets('batch delete and single-step undo', (tester) async {
    await repo.createTask(title: 'A');
    await repo.createTask(title: 'B');
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('batch-delete')));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsNothing);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('AI settings saves provider key and tests connection',
      (tester) async {
    final keyStore = InMemoryAiKeyStore();
    final providerStore = InMemoryAiProviderStore();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        aiKeyStoreProvider.overrideWithValue(keyStore),
        aiProviderStoreProvider.overrideWithValue(providerStore),
        aiClientProvider.overrideWithValue(_FakeAiClient()),
      ],
      child: const LifeOSApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-settings')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-key')), 'sk-test');
    await tester.tap(find.byKey(const Key('ai-save')));
    await tester.pumpAndSettle();

    expect(await keyStore.read('deepseek'), 'sk-test');
    expect(await providerStore.readActiveId(), 'deepseek');

    await tester.tap(find.byKey(const Key('ai-test')));
    await tester.pumpAndSettle();
    expect(find.textContaining('连接成功'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('date picker does not pop the keyboard', (tester) async {
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-title')), 'x');
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('截止日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(tester.testTextInput.isVisible, isFalse);
    await _disposeApp(tester);
  });

  testWidgets('pinned is labeled as list ordering, not long-term',
      (tester) async {
    await tester.pumpWidget(_app(db));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('置顶（任务列表排最前）'), findsOneWidget);
    expect(find.text('置顶（长期任务）'), findsNothing);
    await _disposeApp(tester);
  });
}
