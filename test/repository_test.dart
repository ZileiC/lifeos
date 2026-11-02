import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/database.dart';
import 'package:lifeos/data/repository.dart';
import 'package:lifeos/data/rrule.dart';
import 'package:lifeos/services/notification_service.dart';

/// Test double for the reminder scheduling seam. It records what the
/// repository asked for so recurrence/reminder invariants can be asserted
/// without touching the Android notification plugin.
class _FakeReminderScheduler implements ReminderScheduler {
  final List<({String recordId, List<int> offsets, List<DateTime> instants})>
      scheduled = [];
  final List<String> cancelled = [];

  @override
  Future<ScheduleResult> scheduleForRecord({
    required String recordId,
    required String title,
    required String? timeLabel,
    required List<int> offsets,
    required List<DateTime> instants,
  }) async {
    scheduled.add((
      recordId: recordId,
      offsets: List<int>.unmodifiable(offsets),
      instants: List<DateTime>.unmodifiable(instants),
    ));
    return ScheduleResult(exact: false, scheduled: instants.length);
  }

  @override
  Future<void> cancelForRecord(String recordId) async {
    cancelled.add(recordId);
  }
}

Future<Record> _recordById(AppDatabase db, String id) async =>
    (db.select(db.records)..where((r) => r.id.equals(id))).getSingle();

Future<Record> _nextInstanceOf(AppDatabase db, String originId) async {
  final origin = await _recordById(db, originId);
  return _recordById(db, origin.nextInstanceId!);
}

void main() {
  late AppDatabase db;
  late RecordRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RecordRepository(db);
  });

  tearDown(() async => db.close());

  group('F1 时间区间', () {
    test('创建带区间的记录，startAt/endAt 落库', () async {
      final due = DateTime(2026, 9, 10);
      final start = DateTime(2026, 9, 10, 14, 0);
      final end = DateTime(2026, 9, 10, 15, 50);
      final id = await repo.createRecord(
          title: '上课', dueAt: due, startAt: start, endAt: end);
      final row = await (db.select(db.records)..where((r) => r.id.equals(id)))
          .getSingle();
      expect(row.startAt, start);
      expect(row.endAt, end);
    });

    test('endAt 早于 startAt 自动对调', () async {
      final start = DateTime(2026, 9, 10, 15, 50);
      final end = DateTime(2026, 9, 10, 14, 0);
      final id = await repo.createRecord(
          title: '反的', startAt: start, endAt: end);
      final row = await (db.select(db.records)..where((r) => r.id.equals(id)))
          .getSingle();
      expect(row.startAt!.hour, 14);
      expect(row.endAt!.hour, 15);
    });

    test('区间与 dueAt/rrule 正交：无 dueAt 也能有区间', () async {
      final id = await repo.createRecord(
        title: '只有区间',
        startAt: DateTime(2026, 9, 10, 9, 0),
        endAt: DateTime(2026, 9, 10, 10, 0),
      );
      final row = await (db.select(db.records)..where((r) => r.id.equals(id)))
          .getSingle();
      expect(row.dueAt, isNull);
      expect(row.startAt, isNotNull);
      expect(row.endAt, isNotNull);
    });

    test('updateRecord clearSpan 清空区间', () async {
      final id = await repo.createRecord(
          title: 'x',
          startAt: DateTime(2026, 9, 10, 9),
          endAt: DateTime(2026, 9, 10, 10));
      await repo.updateRecord(id, clearSpan: true);
      final row = await (db.select(db.records)..where((r) => r.id.equals(id)))
          .getSingle();
      expect(row.startAt, isNull);
      expect(row.endAt, isNull);
    });

    test('循环完成：时间段随行到下一次实例（日期推进、时刻保留）', () async {
      // 2026-09-04 is a Friday; weekly(1) rule; span 14:00-15:50.
      final due = DateTime(2026, 9, 4);
      final id = await repo.createRecord(
        title: '每周的会',
        dueAt: due,
        startAt: DateTime(2026, 9, 4, 14, 0),
        endAt: DateTime(2026, 9, 4, 15, 50),
        rrule: const RRule.weekly(1),
      );
      await repo.setCompleted(id, true);

      // Next instance: Monday 2026-09-07.
      final all = await db.select(db.records).get();
      final next = all.firstWhere((r) => r.id != id);
      expect(next.dueAt, DateTime(2026, 9, 7));
      // times kept.
      expect(next.startAt!.hour, 14);
      expect(next.startAt!.minute, 0);
      expect(next.endAt!.hour, 15);
      expect(next.endAt!.minute, 50);
      // date advanced to the next occurrence.
      expect(next.startAt!.day, 7);
      expect(next.endAt!.day, 7);
      // lineage pointer recorded.
      final origin = await (db.select(db.records)..where((r) => r.id.equals(id)))
          .getSingle();
      expect(origin.nextInstanceId, next.id);
    });
  });

  group('F2 时刻精确', () {
    test('dueAt 可带时刻落库；今日视图归属按日粒度', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueWithTime = today.add(const Duration(hours: 14, minutes: 30));
      final id = await repo.createRecord(title: '今天下午', dueAt: dueWithTime);
      final rows = await repo.watchRecords(kind: ViewKind.today).first;
      expect(rows.any((r) => r.record.id == id), isTrue,
          reason: '今天 14:30 应归属今日视图');
    });

    test('仅日期（零点）dueAt 同样归属今日', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final id = await repo.createRecord(title: '今天零点', dueAt: today);
      final rows = await repo.watchRecords(kind: ViewKind.today).first;
      expect(rows.any((r) => r.record.id == id), isTrue);
    });

    test('明天带时刻的 dueAt 不进今日视图', () async {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day)
          .add(const Duration(days: 1, hours: 10));
      final id = await repo.createRecord(title: '明天上午', dueAt: tomorrow);
      final rows = await repo.watchRecords(kind: ViewKind.today).first;
      expect(rows.any((r) => r.record.id == id), isFalse);
    });
  });

  group('F3 撤销完成', () {
    test('普通记录撤销完成：completedAt 置空，回到未完成视图', () async {
      final id = await repo.createRecord(title: '普通');
      await repo.setCompleted(id, true);
      var row = await (db.select(db.records)..where((r) => r.id.equals(id)))
          .getSingle();
      expect(row.completedAt, isNotNull);
      await repo.setCompleted(id, false);
      row = await (db.select(db.records)..where((r) => r.id.equals(id)))
          .getSingle();
      expect(row.completedAt, isNull);
      final inbox = await repo.watchRecords(kind: ViewKind.inbox).first;
      expect(inbox.any((r) => r.record.id == id), isTrue);
    });

    test('循环记录撤销完成：未被编辑过的下一次实例一并回收', () async {
      final id = await repo.createRecord(
          title: '循环', dueAt: DateTime(2026, 9, 4), rrule: const RRule.daily());
      await repo.setCompleted(id, true);
      var all = await db.select(db.records).get();
      expect(all.length, 2, reason: '完成时生成下一次实例');
      final next = all.firstWhere((r) => r.id != id);

      // Undo completion.
      await repo.setCompleted(id, false);
      all = await db.select(db.records).get();

      // The pure-clone instance is tombstone-reclaimed.
      final nextRow = all.firstWhere((r) => r.id == next.id);
      expect(nextRow.deletedAt, isNotNull, reason: '未被编辑过的实例应回收');
      // The origin is back to uncompleted.
      final origin = all.firstWhere((r) => r.id == id);
      expect(origin.completedAt, isNull);
      expect(origin.nextInstanceId, isNull, reason: '血缘指针清空');
      // Back in the open (inbox) view.
      final inbox = await repo.watchRecords(kind: ViewKind.inbox).first;
      expect(inbox.any((r) => r.record.id == id), isTrue);
    });

    test('循环记录撤销完成：被编辑过的下一次实例保留', () async {
      final id = await repo.createRecord(
          title: '循环', dueAt: DateTime(2026, 9, 4), rrule: const RRule.daily());
      await repo.setCompleted(id, true);
      final all = await db.select(db.records).get();
      final next = all.firstWhere((r) => r.id != id);

      // The user did work on the instance: changed the title.
      await repo.updateRecord(next.id, title: '改过的下一次');

      // Undo completion.
      await repo.setCompleted(id, false);
      final after = await db.select(db.records).get();

      // The edited instance survives (deletedAt still null).
      final nextRow = after.firstWhere((r) => r.id == next.id);
      expect(nextRow.deletedAt, isNull, reason: '编辑过的实例应保留');
      expect(nextRow.title, '改过的下一次');
    });

    test('F3b：循环记录在已完成视图撤销完成，纯克隆实例回收（复用 _isPureClone）',
        () async {
      final id = await repo.createRecord(
          title: '周报', dueAt: DateTime(2026, 9, 4), rrule: const RRule.weekly(5));
      await repo.setCompleted(id, true);

      // The row is visible in the done view.
      var doneRows = await repo.watchRecords(kind: ViewKind.done).first;
      expect(doneRows.any((r) => r.record.id == id), isTrue,
          reason: '已完成视图必须有已完成记录（撤销入口的真实场景）');

      // Undo from the done-view context (same setCompleted path as inbox).
      await repo.setCompleted(id, false);

      // It leaves the done view and returns to the open view.
      doneRows = await repo.watchRecords(kind: ViewKind.done).first;
      expect(doneRows.any((r) => r.record.id == id), isFalse,
          reason: '撤销后应离开已完成视图');
      final inbox = await repo.watchRecords(kind: ViewKind.inbox).first;
      expect(inbox.any((r) => r.record.id == id), isTrue,
          reason: '撤销后按规则回到收件箱');

// see test name
      final all = await db.select(db.records).get();
      final nextRow = all.firstWhere((r) => r.rrule != null && r.id != id);
      expect(nextRow.deletedAt, isNotNull, reason: '纯克隆实例应回收');
    });
  });

  group('F1b 时间段两步交互（数据层契约）', () {
    test('可只设开始不设结束', () async {
      final id = await repo.createRecord(
          title: '只有开始',
          startAt: DateTime(2026, 9, 10, 9, 0));
      final row = await (db.select(db.records)..where((r) => r.id.equals(id)))
          .getSingle();
      expect(row.startAt!.hour, 9);
      expect(row.endAt, isNull);
    });

    test('F1c：区间可带日期轴，不锚定 dueAt（存完整时间戳）', () async {
      // dueAt is 9/4 while the span starts 9/10 14:00 — must persist verbatim.
      final id = await repo.createRecord(
          title: '下节课',
          dueAt: DateTime(2026, 9, 4),
          startAt: DateTime(2026, 9, 10, 14, 0),
          endAt: DateTime(2026, 9, 10, 15, 50));
      final row = await (db.select(db.records)..where((r) => r.id.equals(id)))
          .getSingle();
      expect(row.startAt, DateTime(2026, 9, 10, 14, 0),
          reason: '区间日期轴独立于 dueAt（H1 核心诉求）');
      expect(row.endAt, DateTime(2026, 9, 10, 15, 50));
    });

    test('F1c：跨天区间落库与回读', () async {
      final id = await repo.createRecord(
          title: '出差',
          startAt: DateTime(2026, 9, 10, 20, 0),
          endAt: DateTime(2026, 9, 12, 8, 30));
      final row = await (db.select(db.records)..where((r) => r.id.equals(id)))
          .getSingle();
      expect(row.startAt, DateTime(2026, 9, 10, 20, 0));
      expect(row.endAt, DateTime(2026, 9, 12, 8, 30));
    });

    test('F1c：跨天区间 end 早于 start 按完整时间戳对调（非分钟数）', () async {
      // Start 9-11 08:00, end 9-10 22:00 (end timestamp earlier) -> swap.
      final id = await repo.createRecord(
          title: '反的跨天',
          startAt: DateTime(2026, 9, 11, 8, 0),
          endAt: DateTime(2026, 9, 10, 22, 0));
      final row = await (db.select(db.records)..where((r) => r.id.equals(id)))
          .getSingle();
      expect(row.startAt, DateTime(2026, 9, 10, 22, 0),
          reason: '完整时间戳更早者为开始');
      expect(row.endAt, DateTime(2026, 9, 11, 8, 0));
    });

    test('allDay=true 的循环任务：下一次实例携带全天标记与时刻', () async {
// (see test name)
      final id = await repo.createRecord(
        title: '每天站会',
        dueAt: DateTime(2026, 9, 4),
        allDay: true,
        rrule: const RRule.daily(),
      );
      await repo.setCompleted(id, true);
      final next = (await db.select(db.records).get())
          .firstWhere((r) => r.id != id);
      expect(next.allDay, isTrue, reason: '全天标记随行');
      expect(next.dueAt, DateTime(2026, 9, 5));
      expect(next.startAt, isNull);
    });

    test('allDay=false 的循环任务：下一次实例携带真实 00:00 时刻与全天标记',
        () async {
// see test name
      final id = await repo.createRecord(
        title: '午夜任务',
        dueAt: DateTime(2026, 9, 4, 0, 0),
        allDay: false,
        rrule: const RRule.daily(),
      );
      await repo.setCompleted(id, true);
      final next = (await db.select(db.records).get())
          .firstWhere((r) => r.id != id);
      expect(next.allDay, isFalse, reason: '非全天标记随行');
      expect(next.dueAt!.hour, 0, reason: '真实 00:00 必须保留（废弃零点哨兵）');
      expect(next.dueAt!.minute, 0);
      expect(next.dueAt!.day, 5, reason: '日期推进到下一次');
    });

    test('F1c：循环下一次实例——区间带日期轴时日期推进、时刻保留', () async {
// see test name
      final id = await repo.createRecord(
        title: '下周的会',
        dueAt: DateTime(2026, 9, 4),
        startAt: DateTime(2026, 9, 10, 14, 0),
        endAt: DateTime(2026, 9, 10, 15, 50),
        rrule: const RRule.weekly(1),
      );
      await repo.setCompleted(id, true);
      final next = (await db.select(db.records).get())
          .firstWhere((r) => r.id != id);
      // Due advances to 9-7 (next Monday); the span advances the same 3 days.
      expect(next.dueAt, DateTime(2026, 9, 7));
      expect(next.startAt, DateTime(2026, 9, 13, 14, 0),
          reason: '区间日期随到期推进 3 天，时刻保留');
      expect(next.endAt, DateTime(2026, 9, 13, 15, 50));
    });

    test('F1c：跨天循环区间——下一次实例保持跨度', () async {
// see test name
      final id = await repo.createRecord(
        title: '出差循环',
        dueAt: DateTime(2026, 9, 4),
        startAt: DateTime(2026, 9, 10, 20, 0),
        endAt: DateTime(2026, 9, 12, 8, 30),
        rrule: const RRule.daily(),
      );
      await repo.setCompleted(id, true);
      final next = (await db.select(db.records).get())
          .firstWhere((r) => r.id != id);
      // Due advances 1 day (9-5); new start = 9-11 20:00 (span advanced too).
      expect(next.startAt, DateTime(2026, 9, 11, 20, 0));
      // Span kept at 2 days: new end = 9-13 08:30.
      expect(next.endAt, DateTime(2026, 9, 13, 8, 30),
          reason: '跨天区间的天数差在下一次实例中保持');
    });

    test('F1c：跨天循环区间边界——区间开始早于 dueAt（过期的区间）', () async {
// see test name
      final id = await repo.createRecord(
        title: '过期区间循环',
        dueAt: DateTime(2026, 9, 10),
        startAt: DateTime(2026, 9, 4, 9, 0),
        endAt: DateTime(2026, 9, 4, 11, 0),
        rrule: const RRule.daily(),
      );
      await repo.setCompleted(id, true);
      final next = (await db.select(db.records).get())
          .firstWhere((r) => r.id != id);
      // Due advances 1 day (9-11); the span advances 1 day too -> 9-5 (no re-anchoring).
      expect(next.startAt, DateTime(2026, 9, 5, 9, 0),
          reason: '区间按原相对关系推进，不锚定到期日');
      expect(next.endAt, DateTime(2026, 9, 5, 11, 0));
    });

    test('F1c：只设开始的循环——下一次实例开始随行、结束仍空', () async {
      final id = await repo.createRecord(
        title: '只有开始循环',
        dueAt: DateTime(2026, 9, 4),
        startAt: DateTime(2026, 9, 4, 14, 0),
        rrule: const RRule.daily(),
      );
      await repo.setCompleted(id, true);
      final next = (await db.select(db.records).get())
          .firstWhere((r) => r.id != id);
      expect(next.startAt, DateTime(2026, 9, 5, 14, 0));
      expect(next.endAt, isNull);
    });
  });

  group('F4 批量操作', () {
    test('批量完成：多条含循环的记录逐条走单条逻辑（实例生成一致）', () async {
      final a = await repo.createRecord(
          title: 'A', dueAt: DateTime(2026, 9, 4), rrule: const RRule.daily());
      final b = await repo.createRecord(title: 'B');
      final c = await repo.createRecord(
          title: 'C', dueAt: DateTime(2026, 9, 4), rrule: const RRule.daily());

      await repo.setCompletedBulk([a, b, c], true);

      final all = await db.select(db.records).get();
// see test name
      expect(all.length, 5, reason: '循环任务批量完成的实例生成与单条一致');
      expect(all.firstWhere((r) => r.id == a).completedAt, isNotNull);
      expect(all.firstWhere((r) => r.id == b).completedAt, isNotNull);
      expect(all.firstWhere((r) => r.id == c).completedAt, isNotNull);
    });

    test('批量取消完成：循环记录的纯克隆实例逐条回收', () async {
      final a = await repo.createRecord(
          title: 'A', dueAt: DateTime(2026, 9, 4), rrule: const RRule.daily());
      final b = await repo.createRecord(
          title: 'B', dueAt: DateTime(2026, 9, 4), rrule: const RRule.daily());
      await repo.setCompletedBulk([a, b], true);
      var all = await db.select(db.records).get();
      expect(all.length, 4);

      await repo.setCompletedBulk([a, b], false);
      all = await db.select(db.records).get();
// (see test name)
      expect(all.length, 4);
      final live = all.where((r) => r.deletedAt == null).toList();
      expect(live.length, 2, reason: '只剩两条原记录');
      expect(live.every((r) => r.completedAt == null), isTrue);
    });

    test('批量删除：全部墓碑化', () async {
      final a = await repo.createRecord(title: 'A');
      final b = await repo.createRecord(title: 'B');
      await repo.deleteRecordsBulk([a, b]);
      final all = await db.select(db.records).get();
      expect(all.length, 2, reason: '墓碑不物理删除');
      expect(all.every((r) => r.deletedAt != null), isTrue);
      final inbox = await repo.watchRecords(kind: ViewKind.inbox).first;
      expect(inbox, isEmpty);
    });
  });

  group('L2 循环提醒：下一实例持久化 reminderOffsets', () {
    test('完成循环任务：下一实例持久化 reminderOffsets', () async {
      final fake = _FakeReminderScheduler();
      final r = RecordRepository(db, reminders: fake);
      final due = DateTime.now().add(const Duration(days: 2));
      final id = await r.createRecord(
        title: '循环提醒',
        dueAt: due,
        allDay: false,
        rrule: const RRule.daily(),
        reminderOffsets: const [15, 60],
      );

      await r.setCompleted(id, true);

      final next = await _nextInstanceOf(db, id);
      expect(next.reminderOffsets, '15,60',
          reason: '下一实例必须继承提醒提前量（D1）');
      final calls = fake.scheduled.where((c) => c.recordId == next.id).toList();
      expect(calls, isNotEmpty, reason: '下一实例的提醒应被排程');
      expect(calls.last.offsets, [15, 60]);
    });

    test('编辑下一实例：仍按原 offsets 重排，不被空列表取消', () async {
      final fake = _FakeReminderScheduler();
      final r = RecordRepository(db, reminders: fake);
      final due = DateTime.now().add(const Duration(days: 2));
      final id = await r.createRecord(
        title: '循环提醒',
        dueAt: due,
        allDay: false,
        rrule: const RRule.daily(),
        reminderOffsets: const [15, 60],
      );
      await r.setCompleted(id, true);
      final next = await _nextInstanceOf(db, id);
      final callsBefore =
          fake.scheduled.where((c) => c.recordId == next.id).length;

      await r.updateRecord(next.id, title: '改过标题');

      final callsAfter =
          fake.scheduled.where((c) => c.recordId == next.id).toList();
      expect(callsAfter.length, greaterThan(callsBefore),
          reason: '编辑后应重新排程，而不是取消');
      expect(callsAfter.last.offsets, [15, 60]);
      expect(fake.cancelled, isNot(contains(next.id)),
          reason: '仍有提醒的下一实例不应被取消');
      final refreshed = await _recordById(db, next.id);
      expect(refreshed.reminderOffsets, '15,60');
    });

    test('连续两代：下下次实例仍携带 offsets', () async {
      final fake = _FakeReminderScheduler();
      final r = RecordRepository(db, reminders: fake);
      final due = DateTime.now().add(const Duration(days: 2));
      final id = await r.createRecord(
        title: '循环提醒',
        dueAt: due,
        allDay: false,
        rrule: const RRule.daily(),
        reminderOffsets: const [15, 60],
      );
      await r.setCompleted(id, true);
      final next1 = await _nextInstanceOf(db, id);

      await r.setCompleted(next1.id, true);

      final next2 = await _nextInstanceOf(db, next1.id);
      expect(next2.reminderOffsets, '15,60',
          reason: '第二代实例仍须继承 offsets（D1 断代回归）');
      final calls = fake.scheduled.where((c) => c.recordId == next2.id);
      expect(calls, isNotEmpty);
      expect(calls.last.offsets, [15, 60]);
    });
  });

  group('L2 撤销完成：回收实例取消通知', () {
    test('撤销完成回收纯克隆实例：取消该实例的通知', () async {
      final fake = _FakeReminderScheduler();
      final r = RecordRepository(db, reminders: fake);
      final due = DateTime.now().add(const Duration(days: 2));
      final id = await r.createRecord(
        title: '循环提醒',
        dueAt: due,
        allDay: false,
        rrule: const RRule.daily(),
        reminderOffsets: const [15, 60],
      );
      await r.setCompleted(id, true);
      final next = await _nextInstanceOf(db, id);

      await r.setCompleted(id, false);

      final reclaimed = await _recordById(db, next.id);
      expect(reclaimed.deletedAt, isNotNull, reason: '纯克隆实例应被回收');
      expect(fake.cancelled, contains(next.id),
          reason: '回收后必须取消其已排提醒（D3 幽灵提醒回归）');
    });

    test('编辑过的下一实例保留：不得取消其通知', () async {
      final fake = _FakeReminderScheduler();
      final r = RecordRepository(db, reminders: fake);
      final due = DateTime.now().add(const Duration(days: 2));
      final id = await r.createRecord(
        title: '循环提醒',
        dueAt: due,
        allDay: false,
        rrule: const RRule.daily(),
        reminderOffsets: const [15, 60],
      );
      await r.setCompleted(id, true);
      final next = await _nextInstanceOf(db, id);
      await r.updateRecord(next.id, title: '改过标题');

      await r.setCompleted(id, false);

      final kept = await _recordById(db, next.id);
      expect(kept.deletedAt, isNull, reason: '编辑过的实例有真实工作，不回收');
      expect(fake.cancelled, isNot(contains(next.id)),
          reason: '保留的实例不得被取消通知');
    });

    test('只改下一实例提醒：视为有编辑，保留且不取消', () async {
      final fake = _FakeReminderScheduler();
      final r = RecordRepository(db, reminders: fake);
      final due = DateTime.now().add(const Duration(days: 2));
      final id = await r.createRecord(
        title: '循环提醒',
        dueAt: due,
        allDay: false,
        rrule: const RRule.daily(),
        reminderOffsets: const [15, 60],
      );
      await r.setCompleted(id, true);
      final next = await _nextInstanceOf(db, id);

      await r.updateRecord(next.id, reminderOffsetsParam: const [30]);
      final edited = await _recordById(db, next.id);
      expect(edited.reminderOffsets, '30');

      await r.setCompleted(id, false);

      final kept = await _recordById(db, next.id);
      expect(kept.deletedAt, isNull,
          reason: '只改提醒也是用户编辑，不得按纯克隆回收');
      expect(fake.cancelled, isNot(contains(next.id)),
          reason: '保留的实例不得被取消通知');
    });
  });
}
