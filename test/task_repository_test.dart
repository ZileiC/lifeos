import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/database.dart';
import 'package:lifeos/data/recurrence.dart';
import 'package:lifeos/data/task_colors.dart';
import 'package:lifeos/data/task_math.dart';
import 'package:lifeos/data/task_repository.dart';

Future<Record> _task(AppDatabase db, String id) async =>
    (db.select(db.records)..where((r) => r.id.equals(id))).getSingle();

void main() {
  late AppDatabase db;
  late TaskRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TaskRepository(db);
  });

  tearDown(() async => db.close());

  test('create normal task persists U&I, estimate, color and note', () async {
    final id = await repo.createTask(
      title: '写报告',
      note: '第三章',
      urgency: 7,
      importance: 9,
      dueAt: DateTime(2026, 11, 5, 18),
      dueHasTime: true,
      estimatedMinutes: 120,
    );
    final task = await _task(db, id);

    expect(task.urgency, 7);
    expect(task.importance, 9);
    expect(task.estimatedMinutes, 120);
    expect(task.body, '第三章');
    expect(task.color, TaskColors.forId(id));
    expect(task.recurrence, isNull);
    expect(task.allDay, isFalse);
    expect(task.dueAt, DateTime(2026, 11, 5, 18));
  });

  test('normal task remaining reflects planned slices and over-allocation',
      () async {
    final id = await repo.createTask(
      title: '写报告',
      estimatedMinutes: 120,
    );
    await repo.addSlice(
      taskId: id,
      startAt: DateTime(2026, 11, 3, 9),
      endAt: DateTime(2026, 11, 3, 10),
    );
    final task = await _task(db, id);
    final slices = await repo.watchSlicesForDay(DateTime(2026, 11, 3)).first;
    final rows = slices.map((entry) => entry.slice);

    expect(TaskMath.plannedMinutes(rows), 60);
    expect(TaskMath.remainingMinutes(task, rows), 60);
    expect(TaskMath.isOverAllocated(task, rows), isFalse);

    await repo.addSlice(
      taskId: id,
      startAt: DateTime(2026, 11, 4, 9),
      endAt: DateTime(2026, 11, 4, 11),
    );
    final all = await db.select(db.daySlices).get();
    expect(TaskMath.plannedMinutes(all), 180);
    expect(TaskMath.remainingMinutes(task, all), 0);
    expect(TaskMath.isOverAllocated(task, all), isTrue);
  });

  test('weekly-fixed task generates same-color slices and per-occurrence meta',
      () async {
    final spec = RecurrenceSpec(
      weekdays: {1, 3, 5},
      startMinutes: 9 * 60,
      durationMinutes: 60,
      fromDate: DateTime(2026, 11, 2),
      toDate: DateTime(2026, 11, 8),
    );
    final id = await repo.createTask(title: '课', recurrence: spec);
    final task = await _task(db, id);

    expect(task.recurrence, isNotNull);
    expect(task.estimatedMinutes, 60);
    expect(task.dueAt, DateTime(2026, 11, 8));
    expect(TaskMath.remainingMinutes(task, const []), isNull);

    final all = await db.select(db.daySlices).get();
    expect(all, hasLength(3));
    expect(all.every((slice) => slice.taskId == id), isTrue);

    final monday = await repo.watchSlicesForDay(DateTime(2026, 11, 2)).first;
    expect(monday, hasLength(1));
    expect(monday.first.task.color, task.color);
    expect(monday.first.slice.startAt, DateTime(2026, 11, 2, 9));
    expect(monday.first.slice.endAt, DateTime(2026, 11, 2, 10));
  });

  test('editing a weekly-fixed template does not regenerate existing slices',
      () async {
    final spec = RecurrenceSpec(
      weekdays: {1},
      startMinutes: 8 * 60,
      durationMinutes: 60,
      fromDate: DateTime(2026, 11, 2),
      toDate: DateTime(2026, 11, 16),
    );
    final id = await repo.createTask(title: '课', recurrence: spec);
    final before = await db.select(db.daySlices).get();
    expect(before, hasLength(3));

    await repo.updateTask(id, title: '新课名');
    final after = await db.select(db.daySlices).get();
    final task = await _task(db, id);

    expect(after, hasLength(3));
    expect(task.title, '新课名');
  });

  test('delete and restore tasks + their slices', () async {
    final id = await repo.createTask(title: 'A', estimatedMinutes: 60);
    await repo.addSlice(
      taskId: id,
      startAt: DateTime(2026, 11, 3, 9),
      endAt: DateTime(2026, 11, 3, 10),
    );

    final token = await repo.deleteTasks([id]);
    expect(await repo.watchActiveTasks().first, isEmpty);
    expect(await repo.watchSlicesForDay(DateTime(2026, 11, 3)).first, isEmpty);

    await repo.restoreTasks(token);
    expect((await repo.watchActiveTasks().first).map((t) => t.id), contains(id));
    expect(
      await repo.watchSlicesForDay(DateTime(2026, 11, 3)).first,
      hasLength(1),
    );
  });

  test('batch move to day preserves time-of-day; undo restores old due date',
      () async {
    final id = await repo.createTask(
      title: 'A',
      dueAt: DateTime(2026, 11, 10, 14, 30),
      dueHasTime: true,
      estimatedMinutes: 60,
    );

    final snapshots = await repo.moveTasksToDay([id], DateTime(2026, 11, 15));
    final moved = await _task(db, id);
    expect(moved.dueAt, DateTime(2026, 11, 15, 14, 30));
    expect(moved.allDay, isFalse);

    await repo.restoreDueDates(snapshots);
    final restored = await _task(db, id);
    expect(restored.dueAt, DateTime(2026, 11, 10, 14, 30));
  });

  test('active task list sorts pinned first, then urgency', () async {
    final low = await repo.createTask(title: 'low', urgency: 2);
    final high = await repo.createTask(title: 'high', urgency: 9);
    final pinned = await repo.createTask(title: 'pinned', urgency: 1, pinned: true);

    final list = await repo.watchActiveTasks().first;
    expect(list.map((t) => t.id).toList(), [pinned, high, low]);
  });
}
