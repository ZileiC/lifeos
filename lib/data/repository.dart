import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'rrule.dart';

/// 视图种类
enum ViewKind { inbox, today, done }

/// 记录 + 其勾选项的聚合
class RecordWithItems {
  RecordWithItems({required this.record, required this.items});
  final Record record;
  final List<Checkitem> items;
}

/// 数据仓库：全部写操作走这里，保证 UUID / updated_at / 墓碑一致性。
class RecordRepository {
  RecordRepository(this._db);
  final AppDatabase _db;

  static const _uuid = Uuid();

  // 具体生成表类型（$ 前缀是公开名，来自 database 库的 part 文件）
  $RecordsTable get _r => _db.records;
  $CheckitemsTable get _c => _db.checkitems;
  $ListsTable get _l => _db.lists;

  // ---------- 读 ----------

  Expression<bool> _alive() => _r.deletedAt.isNull();

  Expression<bool> _completed() => _r.completedAt.isNotNull();

  /// 指定清单过滤；listId 为 null 时不限清单
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
        // 收件箱 = 未完成的所有活跃记录（今日视图负责按到期聚合高亮）
        where = _alive() & _r.completedAt.isNull() & _inList(listId);
      case ViewKind.today:
        // 今日 = 有到期日且到期日 < 明天零点，未完成
        where = _alive() &
            _r.completedAt.isNull() &
            _inList(listId) &
            _r.dueAt.isNotNull() &
            _r.dueAt.isSmallerThanValue(tomorrow);
      case ViewKind.done:
        // 已完成 = 近 30 天完成的，完成时间倒序
        final since = today.subtract(const Duration(days: 30));
        where = _alive() & _completed() & _r.completedAt.isBiggerOrEqualValue(since);
    }

    final sort = switch (kind) {
      // 未完成视图：置顶优先，然后到期日近的在前，再按创建时间
      ViewKind.inbox || ViewKind.today => [
          OrderingTerm(expression: _r.pinned, mode: OrderingMode.desc),
          OrderingTerm(expression: _r.dueAt, mode: OrderingMode.asc),
          OrderingTerm(expression: _r.createdAt, mode: OrderingMode.desc),
        ],
      ViewKind.done => [
          OrderingTerm(expression: _r.completedAt, mode: OrderingMode.desc),
        ],
    };

    // SimpleSelectStatement.orderBy 需要 OrderClauseGenerator<$RecordsTable>，
    // 把每条 OrderingTerm 包成闭包
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

  // ---------- 记录写 ----------

  Future<String> createRecord({
    required String title,
    String body = '',
    String? listId,
    DateTime? dueAt,
    bool allDay = true,
    DateTime? startAt,
    DateTime? endAt,
    RRule? rrule,
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
            createdAt: now,
            updatedAt: now,
          ));
      for (var i = 0; i < checkitems.length; i++) {
        await _insertCheckitem(
            recordId: id, content: checkitems[i], sortOrder: i, now: now);
      }
    });
    return id;
  }

  /// 时间区间落库前规范化：双边齐时 endAt 早于 startAt 才对调；
  /// 单边（只开始/只结束）原样保留（F1b：可只设开始不设结束）。
  /// 返回 (startAt, endAt)；两者都空返回 null。
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
  }) async {
    final now = DateTime.now();
    // 时间区间：clearSpan 优先；否则传入即整体替换，startAt/endAt 成对规范
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
        updatedAt: Value(now),
      ),
    );
  }

  /// 勾选/取消完成。完成时若带循环规则：生成下一次实例（新 UUID），
  /// 本条作为已完成记录留在历史里。
  ///
  /// 撤销完成（F3）的循环实例回收策略：
  /// 下一次实例**仅在其仍是「纯克隆」时一并墓碑回收**——判定标准 =
  /// 实例的 updatedAt == createdAt（创建后从未被编辑过）。
  /// 理由：纯克隆意味着用户没在它上面做任何工作（没改标题/正文/勾选项状态），
  /// 回收无损失；一旦编辑过，说明用户已经在为下一次做事，回收会毁掉真实工作。
  /// 回收 = 墓碑删除（同步铁律：禁止物理删除）。
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
          // 下一次实例：从到期日（无到期日则从今天）往后推
          final base = row.dueAt ?? now;
          final nextDue = rule.nextAfter(base);
          final nextId = _uuid.v4();
          // F1b：时间段随行——日期推进到 nextDue 的日期，时刻保留原值
          final (nextStart, nextEnd) = _carrySpan(row, nextDue);
          // F2b：全天标记随行
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
          // 循环任务的勾选项带到下一次实例（重置为未勾选）
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
          // 记下「下一次实例」的血缘，供撤销完成时回收判定
          await (_db.update(_r)..where((r) => r.id.equals(id))).write(
            RecordsCompanion(nextInstanceId: Value(nextId), updatedAt: Value(now)),
          );
        }
      } else {
        await (_db.update(_r)..where((r) => r.id.equals(id))).write(
          RecordsCompanion(completedAt: const Value(null), updatedAt: Value(now)),
        );
        // F3：撤销完成时回收「仍是纯克隆」的下一次实例。
        // 纯克隆判定 = 实例内容与原记录模板完全一致（标题/正文/清单/区间/
        // 循环规则 + 全部勾选项文本与状态一致，且实例未完成、未删除）。
        // 不用 updatedAt == createdAt 判定：同一毫秒内创建与编辑时间戳相同，
        // 会把已编辑的实例误判为纯克隆（测试真实暴露过）。
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
          // 清掉血缘指针（无论是否回收，撤销后这条链路已作废）
          await (_db.update(_r)..where((r) => r.id.equals(id))).write(
            RecordsCompanion(nextInstanceId: Value<String?>(null), updatedAt: Value(now)),
          );
        }
      }
    });
  }

  /// F3：纯克隆判定——实例内容与原记录模板一致。
  /// 撤销完成时，纯克隆实例可安全回收；有任何用户加工痕迹则保留。
  /// F2b：allDay 标记纳入比对。F1c：区间按完整时间戳比对（跨天可辨）。
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

  /// F1c：循环生成下一次时的时间段随行。
  /// 推进量 = 下一次到期日 − 原到期日（天数差，可为负）；
  /// 新开始 = 原开始日期 + 推进量，时刻保留；
  /// 跨天区间保持跨度：新结束 = 新开始日期 + 原（结束日期 − 开始日期）天数差，
  /// 时刻保留。无区间原样返回空。
  /// 原记录无到期日时推进量 = 0（区间原样保留）。
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

  /// F4：批量完成/取消完成/删除。逐条走单条逻辑，保证循环任务的
  /// 下一次实例生成与纯克隆回收语义与单条操作完全一致。
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
    // 勾选项也走墓碑，保持同步友好
    final now = DateTime.now();
    await (_db.update(_c)..where((c) => c.id.equals(itemId))).write(
      CheckitemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// 墓碑删除（禁止物理删除）
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
  }

  // ---------- 清单 ----------

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
    // 清单删除是墓碑；其中记录回到收件箱（listId 置空）
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
