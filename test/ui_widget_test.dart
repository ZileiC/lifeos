import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/database.dart';
import 'package:lifeos/data/task_repository.dart';
import 'package:lifeos/main.dart';
import 'package:lifeos/providers.dart';

Widget _app(AppDatabase db) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const LifeOSApp(),
  );
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
}
