import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'reminders.dart';
import 'rrule.dart';
import '../services/notification_service.dart';

/// View kinds.
enum ViewKind { inbox, today, done }

/// Record + its checkitems aggregate.
class RecordWithItems {
  RecordWithItems({required this.record, required this.items});
  final Record record;
  final List<Checkitem> items;
}

/// Repository: all writes go through here to keep UUID / updated_at /
/// tombstone consistency.
class RecordRepository {
  RecordRepository(this._db);
  final AppDatabase _db;

  static const _uuid = Uuid();

  // Concrete generated table types (the \$ names come from database.g.dart).
  $RecordsTable get _r => _db.records;
  $CheckitemsTable get _c => _db.checkitems;
  $ListsTable get _l => _db.lists;

  // ---------- reads ----------

  Expression<bool> _alive() => _r.deletedAt.isNull();

  Expression<bool> _completed() => _r.completedAt.isNotNull();

  /// Filter by list; null listId = no filter.
  Expression<bool> _inList(String? listId) =>
      listId == null ? const Constant(true) : _r.listId.equals(listId);

  Stream<List<RecordWithItems>> watchRecords({
    required ViewKind kind,
    String? listId,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    Expression<bool> where;
    switch (kind) {
      case ViewKind.inbox:
        // Inbox = all active uncompleted records (today view aggregates by due).
        where = _alive() & _r.completedAt.isNull() & _inList(listId);
      case ViewKind.today:
        // Today = dueAt set and dueAt < tomorrow midnight, uncompleted.
        where = _alive() &
            _r.completedAt.isNull() &
            _inList(listId) &
            _r.dueAt.isNotNull() &
            _r.dueAt.isSmallerThanValue(tomorrow);
      case ViewKind.done:
        // Done = completed within the last 30 days, newest first.
        final since = today.subtract(const Duration(days: 30));
        where = _alive() & _completed() & _r.completedAt.isBiggerOrEqualValue(since);
    }

    final sort = switch (kind) {
      // Open views: pinned first, then earliest due, then newest created.
      ViewKind.inbox || ViewKind.today => [
          OrderingTerm(expression: _r.pinned, mode: OrderingMode.desc),
          OrderingTerm(expression: _r.dueAt, mode: OrderingMode.asc),
          OrderingTerm(expression: _r.createdAt, mode: OrderingMode.desc),
        ],
      ViewKind.done => [
          OrderingTerm(expression: _r.completedAt, mode: OrderingMode.desc),
        ],
    };

    // SimpleSelectStatement.orderBy takes OrderClauseGenerator<$RecordsTable>,
    // wrap each OrderingTerm in a closure.
    final List<OrderClauseGenerator<$RecordsTable>> clauses =
        sort.map((term) => (_) => term).toList();
    final stmt = _db.select(_r)
      ..where((r) => where)
      ..orderBy(clauses);

    return stmt.watch().asyncMap(_attachItems);
  }

  Future<List<RecordWithItems>> _attachItems(List<Record> rows) async {
    final result = <RecordWithItems>[];
    for (final record in rows) {
      final items = await (_db.select(_c)
            ..where((c) => c.recordId.equals(record.id) & c.deletedAt.isNull())
            ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
          .get();
      result.add(RecordWithItems(record: record, items: items));
    }
    return result;
  }

  Stream<List<ListRecord>> watchLists() {
    return (_db.select(_l)
          ..where((l) => l.deletedAt.isNull())
          ..orderBy([(l) => OrderingTerm(expression: l.sortOrder)]))
        .watch();
  }

  // ---------- record writes ----------

  Future<String> createRecord({
    required String title,
    String body = '',
    String? listId,
    DateTime? dueAt,
    bool allDay = true,
    DateTime? startAt,
    DateTime? endAt,
    RRule? rrule,
    List<int> reminderOffsets = const [],
    List<String> checkitems = const [],
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final span = _normalizeSpan(dueAt: dueAt, startAt: startAt, endAt: endAt);
    await _db.transaction(() async {
      await _db.into(_r).insert(RecordsCompanion.insert(
            id: id,
            title: title,
            body: Value(body),
            listId: Value(listId),
            allDay: Value(allDay),
            dueAt: Value(dueAt),
            startAt: Value(span?.$1),
            endAt: Value(span?.$2),
            rrule: Value(rrule?.code),
            reminderOffsets: Value(encodeReminderOffsets(reminderOffsets)),
            createdAt: now,
            updatedAt: now,
          ));
      for (var i = 0; i < checkitems.length; i++) {
        await _insertCheckitem(
            recordId: id, content: checkitems[i], sortOrder: i, now: now);
      }
    });
    // L2: schedule reminders for the new record (after commit).
    await _rescheduleReminders(RecordDraft(
      id: id,
      title: title,
      dueAt: dueAt,
      allDay: allDay,
      offsets: reminderOffsets,
    ));
    return id;
  }

  /// Normalize a time span before persisting: with both ends present, swap
  /// when endAt is before startAt; keep single-sided spans as-is (F1b: start
  /// only is allowed). Returns (startAt, endAt); null when both are empty.
  (DateTime?, DateTime?)? _normalizeSpan({
    required DateTime? dueAt,
    required DateTime? startAt,
    required DateTime? endAt,
  }) {
    if (startAt == null && endAt == null) return null;
    var s = startAt;
    var e = endAt;
    if (s != null && e != null && e.isBefore(s)) (s, e) = (e, s);
    return (s, e);
  }

  Future<void> _insertCheckitem({
    required String recordId,
    required String content,
    required int sortOrder,
    required DateTime now,
  }) {
    return _db.into(_c).insert(CheckitemsCompanion.insert(
          id: _uuid.v4(),
          recordId: recordId,
          content: content,
          sortOrder: Value(sortOrder),
          createdAt: now,
          updatedAt: now,
        ));
  }

  Future<void> updateRecord(
    String id, {
    String? title,
    String? body,
    String? listId,
    bool clearList = false,
    DateTime? dueAt,
    bool clearDue = false,
    bool? allDay,
    DateTime? startAt,
    DateTime? endAt,
    bool clearSpan = false,
    RRule? rrule,
    bool clearRrule = false,
    bool? pinned,
    List<int>? reminderOffsetsParam,
    bool clearReminders = false,
  }) async {
    final now = DateTime.now();
    // Time span: clearSpan wins; otherwise replace as a whole with the pair
    // normalized.
    (DateTime?, DateTime?)? span;
    Value<DateTime?> startV = const Value.absent();
    Value<DateTime?> endV = const Value.absent();
    if (clearSpan) {
      startV = const Value(null);
      endV = const Value(null);
    } else if (startAt != null || endAt != null) {
      span = _normalizeSpan(dueAt: dueAt, startAt: startAt, endAt: endAt);
      startV = Value(span?.$1);
      endV = Value(span?.$2);
    }
    await (_db.update(_r)..where((r) => r.id.equals(id))).write(
      RecordsCompanion(
        title: title == null ? const Value.absent() : Value(title),
        body: body == null ? const Value.absent() : Value(body),
        listId: clearList
            ? const Value(null)
            : (listId == null ? const Value.absent() : Value(listId)),
        allDay: allDay == null ? const Value.absent() : Value(allDay),
        dueAt: clearDue
            ? const Value(null)
            : (dueAt == null ? const Value.absent() : Value(dueAt)),
        startAt: startV,
        endAt: endV,
        rrule: clearRrule
            ? const Value(null)
            : (rrule == null ? const Value.absent() : Value(rrule.code)),
        pinned: pinned == null ? const Value.absent() : Value(pinned),
        reminderOffsets: clearReminders
            ? const Value(null)
            : (reminderOffsetsParam == null
                ? const Value.absent()
                : Value(encodeReminderOffsets(reminderOffsetsParam))),
        updatedAt: Value(now),
      ),
    );
    // L2: DDL/time/reminder changes re-schedule notifications.
    final row = await (_db.select(_r)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
    if (row != null) {
      await _rescheduleReminders(RecordDraft(
        id: row.id,
        title: row.title,
        dueAt: row.dueAt,
        allDay: row.allDay,
        offsets: parseReminderOffsets(row.reminderOffsets),
      ));
    }
  }

  /// Mark complete / undo completion. On completion of a recurring record,
  /// spawn the next instance (new UUID); the original stays in history as a
  /// completed row.
  ///
  /// Undo-completion (F3) reclaim policy for the spawned next instance:
  /// it is tombstone-reclaimed only while it is still a "pure clone".
  /// A pure clone means the user has done no work on it (title/body/
  /// checkitems/allDay/span untouched), so reclaiming loses nothing; once
  /// edited, it holds real work and must be kept. Reclaim = tombstone
  /// (sync iron rule: no physical deletes).
  Future<void> setCompleted(String id, bool done) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final row =
          await (_db.select(_r)..where((r) => r.id.equals(id))).getSingle();
      if (done) {
        await (_db.update(_r)..where((r) => r.id.equals(id))).write(
          RecordsCompanion(completedAt: Value(now), updatedAt: Value(now)),
        );
        final rule = RRule.parse(row.rrule);
        if (rule != null) {
          // Next instance: advance from the due date (today if none).
          final base = row.dueAt ?? now;
          final nextDue = rule.nextAfter(base);
          final nextId = _uuid.v4();
          // F1b/F1c: carry the span onto the next instance (times kept).
          final (nextStart, nextEnd) = _carrySpan(row, nextDue);
          // F2b: allDay flag carried over.
          await _db.into(_r).insert(RecordsCompanion.insert(
                id: nextId,
                title: row.title,
                body: Value(row.body),
                listId: Value(row.listId),
                allDay: Value(row.allDay),
                dueAt: Value(nextDue),
                startAt: Value(nextStart),
                endAt: Value(nextEnd),
                rrule: Value(row.rrule),
                createdAt: now,
                updatedAt: now,
              ));
          // Carry checkitems to the next instance (reset to unchecked).
          final items = await (_db.select(_c)
                ..where((c) => c.recordId.equals(row.id) & c.deletedAt.isNull())
                ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
              .get();
          for (final item in items) {
            await _db.into(_c).insert(CheckitemsCompanion.insert(
                  id: _uuid.v4(),
                  recordId: nextId,
                  content: item.content,
                  sortOrder: Value(item.sortOrder),
                  createdAt: now,
                  updatedAt: now,
                ));
          }
          // Record the lineage for undo-completion reclaim.
          await (_db.update(_r)..where((r) => r.id.equals(id))).write(
            RecordsCompanion(nextInstanceId: Value(nextId), updatedAt: Value(now)),
          );
          // L2: schedule reminders for the spawned next instance
          // (its DDL minus lead times). Offsets carried from the origin.
          await _rescheduleReminders(RecordDraft(
            id: nextId,
            title: row.title,
            dueAt: nextDue,
            allDay: row.allDay,
            offsets: parseReminderOffsets(row.reminderOffsets),
          ));
        }
        // L2: the completed origin no longer needs reminders.
        await NotificationService.instance.cancelForRecord(id);
      } else {
        await (_db.update(_r)..where((r) => r.id.equals(id))).write(
          RecordsCompanion(completedAt: const Value(null), updatedAt: Value(now)),
        );
        // L2: back to open — restore reminders per current fields.
        await _rescheduleReminders(RecordDraft(
          id: id,
          title: row.title,
          dueAt: row.dueAt,
          allDay: row.allDay,
          offsets: parseReminderOffsets(row.reminderOffsets),
        ));
        // F3: on undo-completion, reclaim the next instance if it is still a
        // pure clone. Purity is content equality with the origin template
        // (title/body/list/span/rrule + all checkitems, instance uncompleted
        // and undeleted). Timestamp equality is NOT used: same-millisecond
        // create/edit indistinguishable (bitten in a real test).
        final nextId = row.nextInstanceId;
        if (nextId != null) {
          final next = await (_db.select(_r)..where((r) => r.id.equals(nextId)))
              .getSingleOrNull();
          if (next != null &&
              next.deletedAt == null &&
              next.completedAt == null &&
              _isPureClone(row, next)) {
            await (_db.update(_r)..where((r) => r.id.equals(nextId))).write(
              RecordsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
            );
            await (_db.update(_c)..where((c) => c.recordId.equals(nextId))).write(
              CheckitemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
            );
          }
          // Clear the lineage pointer (the chain is void after undo).
          await (_db.update(_r)..where((r) => r.id.equals(id))).write(
            RecordsCompanion(nextInstanceId: Value<String?>(null), updatedAt: Value(now)),
          );
        }
      }
    });
  }

  /// F3 pure-clone test: the instance still matches the origin template.
  /// Pure clones are safe to reclaim on undo-completion; any user edit keeps
  /// the instance. F2b: allDay is compared. F1c: spans compare as full
  /// timestamps (cross-day distinguishable).
  bool _isPureClone(Record origin, Record next) {
    bool sameInstant(DateTime? a, DateTime? b) =>
        (a == null && b == null) ||
        (a != null && b != null && !a.isBefore(b) && !b.isBefore(a));
    return next.title == origin.title &&
        next.body == origin.body &&
        next.listId == origin.listId &&
        next.rrule == origin.rrule &&
        next.pinned == origin.pinned &&
        next.allDay == origin.allDay &&
        sameInstant(origin.startAt, next.startAt) &&
        sameInstant(origin.endAt, next.endAt);
  }

  /// F1c: carry the time span onto the next recurring instance.
  /// Advance = next due minus original due (day delta, may be negative);
  /// new start = original start date + advance, time-of-day kept.
  /// Cross-day spans keep their length: new end = new start date + original
  /// (end date minus start date) day delta, time-of-day kept. No span -> empty.
  /// Without a dueAt the advance is zero (span carried over unchanged).
  (DateTime?, DateTime?) _carrySpan(Record row, DateTime nextDue) {
    final start = row.startAt;
    final end = row.endAt;
    if (start == null && end == null) return (null, null);

    final nextDay = DateTime(nextDue.year, nextDue.month, nextDue.day);
    final due = row.dueAt;
    final advance = due == null
        ? Duration.zero
        : nextDay.difference(DateTime(due.year, due.month, due.day));

    final startDay = DateTime(start!.year, start.month, start.day);
    final newStartDay = startDay.add(advance);
    final newStart = DateTime(newStartDay.year, newStartDay.month,
        newStartDay.day, start.hour, start.minute, start.second);

    if (end == null) return (newStart, null);
    final endDay = DateTime(end.year, end.month, end.day);
    final spanDays = endDay.difference(startDay).inDays;
    final newEndDay = newStartDay.add(Duration(days: spanDays));
    final newEnd = DateTime(newEndDay.year, newEndDay.month, newEndDay.day,
        end.hour, end.minute, end.second);
    return (newStart, newEnd);
  }

  /// F4 bulk complete/undo/delete. Loops the single-item logic so the next-
  /// instance spawn and pure-clone reclaim semantics match single edits.
  Future<void> setCompletedBulk(List<String> ids, bool done) async {
    for (final id in ids) {
      await setCompleted(id, done);
    }
  }

  Future<void> deleteRecordsBulk(List<String> ids) async {
    for (final id in ids) {
      await deleteRecord(id);
    }
  }

  Future<void> toggleCheckitem(String itemId, bool done) async {
    await (_db.update(_c)..where((c) => c.id.equals(itemId))).write(
      CheckitemsCompanion(done: Value(done), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> addCheckitem(String recordId, String text) async {
    final now = DateTime.now();
    final existing = await (_db.select(_c)
          ..where((c) => c.recordId.equals(recordId) & c.deletedAt.isNull()))
        .get();
    await _insertCheckitem(
        recordId: recordId, content: text, sortOrder: existing.length, now: now);
  }

  Future<void> removeCheckitem(String itemId) async {
    // Checkitems are tombstoned too (sync-friendly).
    final now = DateTime.now();
    await (_db.update(_c)..where((c) => c.id.equals(itemId))).write(
      CheckitemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// Tombstone delete (physical deletes are forbidden).
  Future<void> deleteRecord(String id) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_r)..where((r) => r.id.equals(id))).write(
        RecordsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await (_db.update(_c)..where((c) => c.recordId.equals(id))).write(
        CheckitemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
    // L2: deleted records must not fire reminders.
    await NotificationService.instance.cancelForRecord(id);
  }

  /// L2: (re)schedule reminders for one record from its current fields.
  /// Errors are swallowed: a scheduling failure (e.g. plugin not initialized
  /// in tests) must never break the surrounding write.
  Future<void> _rescheduleReminders(RecordDraft draft) async {
    try {
      final instants = computeReminderInstants(
        dueAt: draft.dueAt,
        allDay: draft.allDay,
        offsets: draft.offsets,
      );
      if (instants.isEmpty) {
        await NotificationService.instance.cancelForRecord(draft.id);
        return;
      }
      final timeLabel = _dueTimeLabel(draft.dueAt, draft.allDay);
      await NotificationService.instance.scheduleForRecord(
        recordId: draft.id,
        title: draft.title,
        timeLabel: timeLabel,
        offsets: draft.offsets,
        instants: instants,
      );
    } catch (_) {
      // Never let notification plumbing break a data write.
    }
  }

  /// Notification body time semantics, e.g. "14:00" or "9/10 14:00".
  String? _dueTimeLabel(DateTime? dueAt, bool allDay) {
    if (dueAt == null) return null;
    if (allDay) return '全天';
    final hh = dueAt.hour.toString().padLeft(2, '0');
    final mm = dueAt.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = dueAt.year == now.year &&
        dueAt.month == now.month &&
        dueAt.day == now.day;
    if (sameDay) return '$hh:$mm';
    return '${dueAt.month}月${dueAt.day}日 $hh:$mm';
  }

  // ---------- lists ----------

  Future<String> createList(String name) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final maxRow = await (_db.selectOnly(_l)..addColumns([_l.sortOrder.max()]))
        .getSingle();
    await _db.into(_l).insert(ListsCompanion.insert(
          id: id,
          name: name,
          sortOrder: Value((maxRow.read(_l.sortOrder.max()) ?? -1) + 1),
          createdAt: now,
          updatedAt: now,
        ));
    return id;
  }

  Future<void> renameList(String id, String name) async {
    await (_db.update(_l)..where((l) => l.id.equals(id))).write(
      ListsCompanion(name: Value(name), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> deleteList(String id) async {
    // List delete is a tombstone; its records fall back to the inbox.
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_l)..where((l) => l.id.equals(id))).write(
        ListsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await (_db.update(_r)..where((r) => r.listId.equals(id))).write(
        RecordsCompanion(listId: const Value(null), updatedAt: Value(now)),
      );
    });
  }
}

/// Minimal snapshot of a record's reminder-relevant fields, passed to the
/// notification scheduler after a write.
class RecordDraft {
  RecordDraft({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.allDay,
    required this.offsets,
  });

  final String id;
  final String title;
  final DateTime? dueAt;
  final bool allDay;
  final List<int> offsets;
}
