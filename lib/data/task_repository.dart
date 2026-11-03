import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'recurrence.dart';
import 'task_colors.dart';

/// One day slice joined with its owning task (for the day view).
class DaySliceWithTask {
  const DaySliceWithTask({required this.slice, required this.task});

  final DaySlice slice;
  final Record task;
}

/// Undo token for a batch task delete (tasks + their slices were tombstoned).
class DeleteTasksToken {
  const DeleteTasksToken({required this.taskIds, required this.sliceIds});

  final List<String> taskIds;
  final List<String> sliceIds;
}

/// Snapshot of a task's due date before a batch "move to day" (for undo).
class DueSnapshot {
  const DueSnapshot({
    required this.taskId,
    required this.dueAt,
    required this.allDay,
  });

  final String taskId;
  final DateTime? dueAt;
  final bool allDay;
}

/// All C′ Stage 0 writes go through this repository.
class TaskRepository {
  TaskRepository(this._db);

  final AppDatabase _db;
  static const Uuid _uuid = Uuid();

  $RecordsTable get _r => _db.records;
  $DaySlicesTable get _s => _db.daySlices;

  // ---------- reads ----------

  Stream<List<Record>> watchActiveTasks() {
    final stmt = _db.select(_r)
      ..where((r) => r.deletedAt.isNull() & r.completedAt.isNull())
      ..orderBy([
        (r) => OrderingTerm(expression: r.pinned, mode: OrderingMode.desc),
        (r) => OrderingTerm(expression: r.urgency, mode: OrderingMode.desc),
        (r) => OrderingTerm(expression: r.importance, mode: OrderingMode.desc),
        (r) => OrderingTerm(expression: r.dueAt, mode: OrderingMode.asc),
      ]);
    return stmt.watch();
  }

  Stream<List<DaySliceWithTask>> watchSlicesForDay(DateTime day) {
    final start = _dateOnly(day);
    final end = start.add(const Duration(days: 1));
    final query = _db.select(_s).join([
      innerJoin(_r, _r.id.equalsExp(_s.taskId)),
    ]);
    query.where(_s.deletedAt.isNull() &
        _r.deletedAt.isNull() &
        _s.startAt.isBiggerOrEqualValue(start) &
        _s.startAt.isSmallerThanValue(end));
    query.orderBy([OrderingTerm(expression: _s.startAt)]);
    return query.watch().map((rows) => rows
        .map((row) => DaySliceWithTask(
              slice: row.readTable(_s),
              task: row.readTable(_r),
            ))
        .toList());
  }

  Stream<List<DaySlice>> watchAllSlices() {
    return (_db.select(_s)..where((s) => s.deletedAt.isNull())).watch();
  }

  /// Slices whose startAt falls in [from, to) — used to give the AI the next
  /// 7 days of load. `to` is exclusive.
  Stream<List<DaySliceWithTask>> watchSlicesBetween(
    DateTime from,
    DateTime to,
  ) {
    final start = _dateOnly(from);
    final end = _dateOnly(to);
    final query = _db.select(_s).join([
      innerJoin(_r, _r.id.equalsExp(_s.taskId)),
    ]);
    query.where(_s.deletedAt.isNull() &
        _r.deletedAt.isNull() &
        _s.startAt.isBiggerOrEqualValue(start) &
        _s.startAt.isSmallerThanValue(end));
    query.orderBy([OrderingTerm(expression: _s.startAt)]);
    return query.watch().map((rows) => rows
        .map((row) => DaySliceWithTask(
              slice: row.readTable(_s),
              task: row.readTable(_r),
            ))
        .toList());
  }

  // ---------- task writes ----------

  Future<String> createTask({
    required String title,
    String note = '',
    int? urgency,
    int? importance,
    DateTime? dueAt,
    bool dueHasTime = true,
    int? estimatedMinutes,
    bool pinned = false,
    RecurrenceSpec? recurrence,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final recurring = recurrence;
    final resolvedDue = recurring == null ? dueAt : _dateOnly(recurring.toDate);
    final resolvedAllDay = recurring == null ? !dueHasTime : true;
    final resolvedEstimate =
        recurring?.durationMinutes ?? estimatedMinutes;

    await _db.transaction(() async {
      await _db.into(_r).insert(RecordsCompanion.insert(
            id: id,
            title: title,
            body: Value(note),
            pinned: Value(pinned),
            allDay: Value(resolvedAllDay),
            dueAt: Value(resolvedDue),
            urgency: Value(urgency),
            importance: Value(importance),
            estimatedMinutes: Value(resolvedEstimate),
            color: Value(TaskColors.forId(id)),
            recurrence: Value(
              recurring == null ? null : jsonEncode(recurring.toJson()),
            ),
            createdAt: now,
            updatedAt: now,
          ));
      if (recurring != null) {
        await _generateSlices(id, recurring, now);
      }
    });
    return id;
  }

  Future<void> updateTask(
    String id, {
    String? title,
    String? note,
    int? urgency,
    int? importance,
    DateTime? dueAt,
    bool? dueHasTime,
    int? estimatedMinutes,
    bool? pinned,
    RecurrenceSpec? recurrence,
    bool clearRecurrence = false,
  }) async {
    final now = DateTime.now();
    Value<DateTime?> dueValue =
        dueAt == null ? const Value.absent() : Value(dueAt);
    Value<bool> allDayValue =
        dueHasTime == null ? const Value.absent() : Value(!dueHasTime);
    Value<int?> estimateValue = estimatedMinutes == null
        ? const Value.absent()
        : Value(estimatedMinutes);

    Value<String?> recurrenceValue;
    if (clearRecurrence) {
      recurrenceValue = const Value(null);
    } else if (recurrence != null) {
      recurrenceValue = Value(jsonEncode(recurrence.toJson()));
      dueValue = Value(_dateOnly(recurrence.toDate));
      allDayValue = const Value(true);
      estimateValue = Value(recurrence.durationMinutes);
    } else {
      recurrenceValue = const Value.absent();
    }

    await (_db.update(_r)..where((r) => r.id.equals(id))).write(
      RecordsCompanion(
        title: title == null ? const Value.absent() : Value(title),
        body: note == null ? const Value.absent() : Value(note),
        urgency: urgency == null ? const Value.absent() : Value(urgency),
        importance:
            importance == null ? const Value.absent() : Value(importance),
        dueAt: dueValue,
        allDay: allDayValue,
        estimatedMinutes: estimateValue,
        pinned: pinned == null ? const Value.absent() : Value(pinned),
        recurrence: recurrenceValue,
        updatedAt: Value(now),
      ),
    );
  }

  /// Generation is idempotent: a tombstoned slice still blocks re-insertion,
  /// so a single-day deletion does not come back on a later create.
  Future<void> _generateSlices(
    String taskId,
    RecurrenceSpec spec,
    DateTime now,
  ) async {
    for (final occurrence in RecurrencePlanner.occurrences(spec)) {
      final existing = await (_db.select(_s)
            ..where((slice) =>
                slice.taskId.equals(taskId) &
                slice.startAt.equals(occurrence.startAt)))
          .get();
      if (existing.isNotEmpty) continue;
      await _db.into(_s).insert(DaySlicesCompanion.insert(
            id: _uuid.v4(),
            taskId: taskId,
            startAt: occurrence.startAt,
            endAt: occurrence.endAt,
            createdAt: now,
            updatedAt: now,
          ));
    }
  }

  // ---------- slice writes ----------

  Future<String> addSlice({
    required String taskId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    if (!endAt.isAfter(startAt)) {
      throw ArgumentError('endAt must be after startAt');
    }
    final now = DateTime.now();
    final id = _uuid.v4();
    await _db.into(_s).insert(DaySlicesCompanion.insert(
          id: id,
          taskId: taskId,
          startAt: startAt,
          endAt: endAt,
          createdAt: now,
          updatedAt: now,
        ));
    return id;
  }

  Future<void> updateSlice(
    String id, {
    DateTime? startAt,
    DateTime? endAt,
  }) async {
    final current = await (_db.select(_s)..where((s) => s.id.equals(id)))
        .getSingleOrNull();
    if (current == null) return;
    final nextStart = startAt ?? current.startAt;
    final nextEnd = endAt ?? current.endAt;
    if (!nextEnd.isAfter(nextStart)) {
      throw ArgumentError('endAt must be after startAt');
    }
    await (_db.update(_s)..where((s) => s.id.equals(id))).write(
      DaySlicesCompanion(
        startAt: Value(nextStart),
        endAt: Value(nextEnd),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteSlice(String id) async {
    final now = DateTime.now();
    await (_db.update(_s)..where((s) => s.id.equals(id))).write(
      DaySlicesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  // ---------- batch operations (single-step undo tokens) ----------

  Future<DeleteTasksToken> deleteTasks(List<String> ids) async {
    if (ids.isEmpty) {
      return const DeleteTasksToken(taskIds: [], sliceIds: []);
    }
    final now = DateTime.now();
    final slices = await (_db.select(_s)
          ..where((s) => s.taskId.isIn(ids) & s.deletedAt.isNull()))
        .get();
    final sliceIds = slices.map((s) => s.id).toList();

    await _db.transaction(() async {
      await (_db.update(_r)..where((r) => r.id.isIn(ids))).write(
        RecordsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      if (sliceIds.isNotEmpty) {
        await (_db.update(_s)..where((s) => s.id.isIn(sliceIds))).write(
          DaySlicesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
      }
    });
    return DeleteTasksToken(taskIds: List<String>.of(ids), sliceIds: sliceIds);
  }

  Future<void> restoreTasks(DeleteTasksToken token) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      if (token.taskIds.isNotEmpty) {
        await (_db.update(_r)..where((r) => r.id.isIn(token.taskIds))).write(
          RecordsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }
      if (token.sliceIds.isNotEmpty) {
        await (_db.update(_s)..where((s) => s.id.isIn(token.sliceIds))).write(
          DaySlicesCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  Future<List<DueSnapshot>> moveTasksToDay(
    List<String> ids,
    DateTime day,
  ) async {
    if (ids.isEmpty) return const <DueSnapshot>[];
    final tasks =
        await (_db.select(_r)..where((r) => r.id.isIn(ids))).get();
    final snapshots = <DueSnapshot>[];
    final now = DateTime.now();

    await _db.transaction(() async {
      for (final task in tasks) {
        snapshots.add(DueSnapshot(
          taskId: task.id,
          dueAt: task.dueAt,
          allDay: task.allDay,
        ));
        final hadTime = task.dueAt != null && !task.allDay;
        final newDue = hadTime
            ? DateTime(
                day.year, day.month, day.day, task.dueAt!.hour, task.dueAt!.minute)
            : _dateOnly(day);
        await (_db.update(_r)..where((r) => r.id.equals(task.id))).write(
          RecordsCompanion(
            dueAt: Value(newDue),
            allDay: Value(!hadTime),
            updatedAt: Value(now),
          ),
        );
      }
    });
    return snapshots;
  }

  Future<void> restoreDueDates(List<DueSnapshot> snapshots) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      for (final snapshot in snapshots) {
        await (_db.update(_r)..where((r) => r.id.equals(snapshot.taskId))).write(
          RecordsCompanion(
            dueAt: Value(snapshot.dueAt),
            allDay: Value(snapshot.allDay),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}
