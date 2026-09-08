import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/database.dart';

/// 一个不动 schema 的空迁移策略：阻止 drift 在打开连接时自动建全量表，
/// 用于先造出「旧库」再跑升级。
class _NoopMigration extends MigrationStrategy {
  _NoopMigration() : super(onCreate: (_) async {}, onUpgrade: (m, f, t) async {});
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('schemaVersion = 3', () {
    expect(db.schemaVersion, 3);
  });

  test('v3 schema：records 含 v0.1.1 三列 + v0.1.2 allDay，且新列可空', () async {
    final info = await db.customSelect('PRAGMA table_info(records)').get();
    final cols = info.map((r) => r.data['name'] as String).toSet();
    expect(cols, containsAll([
      'start_at',
      'end_at',
      'next_instance_id',
      'all_day', // v0.1.2 F2b
    ]));

    await db.into(db.records).insert(RecordsCompanion.insert(
          id: 'legacy-like',
          title: '无新区记录',
          createdAt: DateTime(2026, 9, 10),
          updatedAt: DateTime(2026, 9, 10),
        ));
    final row = await (db.select(db.records)
          ..where((r) => r.id.equals('legacy-like')))
        .getSingle();
    expect(row.startAt, isNull);
    expect(row.endAt, isNull);
    expect(row.nextInstanceId, isNull);
    // allDay 有默认值 true（全天），非空
    expect(row.allDay, isTrue);
  });

  test('v1->v3：v1 旧库全链升级后五列生效、旧数据完好', () async {
    final raw = NativeDatabase.memory();
    final v1 = AppDatabase.forTesting(raw, migrationOverride: _NoopMigration());

    // 手工建 v1 形态的 records 表（无 v0.1.1 三新列、无 all_day）并塞一条旧数据
    await v1.customStatement('''
      CREATE TABLE records (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        list_id TEXT NULL,
        pinned INTEGER NOT NULL DEFAULT 0,
        due_at INTEGER NULL,
        rrule TEXT NULL,
        completed_at INTEGER NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      )
    ''');
    await v1.customStatement('''
      INSERT INTO records (id, title, body, pinned, created_at, updated_at)
      VALUES ('v1row', '旧数据', '', 0, 1756900000000, 1756900000000)
    ''');

    // 真实升级链：from=1 一路升到当前版本（v1->v2 再 v2->v3）
    final m = v1.createMigrator();
    await v1.migrateV1ToV2(m, 1, 3);
    await v1.migrateV2ToV3(m, 1, 3);

    final cols = await v1.customSelect('PRAGMA table_info(records)').get();
    final names = cols.map((r) => r.data['name'] as String).toSet();
    expect(names, containsAll(['start_at', 'end_at', 'next_instance_id', 'all_day']));

    final rows = await v1.select(v1.records).get();
    expect(rows, hasLength(1));
    expect(rows.first.id, 'v1row');
    expect(rows.first.title, '旧数据');
    expect(rows.first.startAt, isNull);
    expect(rows.first.nextInstanceId, isNull);
    expect(rows.first.allDay, isTrue, reason: 'v1 旧数据无 due_at → 回填全天');
    await v1.close();
  });

  test('v2->v3：allDay 列加入并按零点哨兵回填（带时刻→非全天，零点/空→全天）',
      () async {
    final raw = NativeDatabase.memory();
    final v2 = AppDatabase.forTesting(raw, migrationOverride: _NoopMigration());

    // 手工建 v2 形态的 records 表（有 v0.1.1 三列，无 all_day）
    await v2.customStatement('''
      CREATE TABLE records (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        list_id TEXT NULL,
        pinned INTEGER NOT NULL DEFAULT 0,
        due_at INTEGER NULL,
        start_at INTEGER NULL,
        end_at INTEGER NULL,
        rrule TEXT NULL,
        next_instance_id TEXT NULL,
        completed_at INTEGER NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER NULL
      )
    ''');
    // drift 的 dateTime 存储为 unix 秒（integer）
    final tZero = DateTime(2026, 9, 4).millisecondsSinceEpoch ~/ 1000; // 零点
    final tTime = DateTime(2026, 9, 4, 14, 30).millisecondsSinceEpoch ~/ 1000;
    await v2.customStatement('''
      INSERT INTO records (id, title, body, pinned, due_at, created_at, updated_at)
      VALUES ('v2-allday', '全天旧数据', '', 0, $tZero, 1756900000000, 1756900000000)
    ''');
    await v2.customStatement('''
      INSERT INTO records (id, title, body, pinned, due_at, created_at, updated_at)
      VALUES ('v2-withtime', '带时刻旧数据', '', 0, $tTime, 1756900000000, 1756900000000)
    ''');
    await v2.customStatement('''
      INSERT INTO records (id, title, body, pinned, due_at, created_at, updated_at)
      VALUES ('v2-nodue', '无到期旧数据', '', 0, NULL, 1756900000000, 1756900000000)
    ''');

    final m = v2.createMigrator();
    await v2.migrateV2ToV3(m, 2, 3);

    // all_day 列存在于物理 schema
    final cols = await v2.customSelect('PRAGMA table_info(records)').get();
    final names = cols.map((r) => r.data['name'] as String).toSet();
    expect(names, contains('all_day'));

    // 回填语义：零点 → 全天(true)；带时刻 → 非全天(false)；无到期 → 全天
    final rows = await v2.select(v2.records).get();
    final byId = {for (final r in rows) r.id: r};
    expect(byId['v2-allday']!.allDay, isTrue, reason: 'v2 零点哨兵 → 全天');
    expect(byId['v2-withtime']!.allDay, isFalse, reason: 'v2 带时刻 → 非全天');
    expect(byId['v2-nodue']!.allDay, isTrue, reason: '无到期 → 全天');
    await v2.close();
  });
}
