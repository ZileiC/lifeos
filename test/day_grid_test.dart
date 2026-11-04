import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/database.dart';
import 'package:lifeos/data/task_repository.dart';
import 'package:lifeos/ui/day_grid.dart';
import 'package:lifeos/ui/theme.dart';

Record _task({String id = 't1', int? color}) {
  final now = DateTime(2026, 11, 1);
  return Record(
    id: id,
    title: 'Task $id',
    body: '',
    listId: null,
    pinned: false,
    allDay: true,
    dueAt: null,
    startAt: null,
    endAt: null,
    rrule: null,
    nextInstanceId: null,
    reminderOffsets: null,
    urgency: 5,
    importance: 5,
    estimatedMinutes: 60,
    color: color,
    recurrence: null,
    completedAt: null,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

DaySlice _slice({
  String id = 's1',
  String taskId = 't1',
  required DateTime start,
  required DateTime end,
}) {
  final now = DateTime(2026, 11, 1);
  return DaySlice(
    id: id,
    taskId: taskId,
    startAt: start,
    endAt: end,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('empty day still renders the 24h base grid and now line',
      (tester) async {
    await tester.pumpWidget(_wrap(DayGrid(
      day: DateTime(2026, 11, 4),
      slices: const [],
      isToday: true,
      now: DateTime(2026, 11, 4, 9, 30),
      onEditSlice: (_) {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('23:00'), findsOneWidget);
    expect(find.byKey(const Key('day-now-line')), findsOneWidget);
    expect(find.text('现在'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('slice renders as a time block with the task color',
      (tester) async {
    final task = _task(color: 0xFF7FA7C9);
    final slice = _slice(
      start: DateTime(2026, 11, 4, 9),
      end: DateTime(2026, 11, 4, 10),
    );
    await tester.pumpWidget(_wrap(DayGrid(
      day: DateTime(2026, 11, 4),
      slices: [DaySliceWithTask(slice: slice, task: task)],
      isToday: false,
      now: DateTime(2026, 11, 4, 12),
      onEditSlice: (_) {},
    )));
    await tester.pumpAndSettle();

    final block = find.byKey(Key('day-block-${slice.id}'));
    expect(block, findsOneWidget);
    expect(find.text('Task t1'), findsOneWidget);
    expect(find.text('09:00–10:00'), findsOneWidget);

    final material = tester.widget<Material>(
      find.ancestor(of: block, matching: find.byType(Material)).first,
    );
    expect(material.color, const Color(0xFF7FA7C9));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('overlapping slices get a warning border', (tester) async {
    final task = _task();
    final first = _slice(
      id: 's1',
      start: DateTime(2026, 11, 4, 9),
      end: DateTime(2026, 11, 4, 10),
    );
    final second = _slice(
      id: 's2',
      start: DateTime(2026, 11, 4, 9, 30),
      end: DateTime(2026, 11, 4, 10, 30),
    );
    await tester.pumpWidget(_wrap(DayGrid(
      day: DateTime(2026, 11, 4),
      slices: [
        DaySliceWithTask(slice: first, task: task),
        DaySliceWithTask(slice: second, task: task),
      ],
      isToday: false,
      now: DateTime(2026, 11, 4, 12),
      onEditSlice: (_) {},
    )));
    await tester.pumpAndSettle();

    final material = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const Key('day-block-s1')),
            matching: find.byType(Material),
          )
          .first,
    );
    final shape = material.shape as RoundedRectangleBorder;
    expect(shape.side.width, 1.5);

    await tester.pumpWidget(const SizedBox());
  });
}
