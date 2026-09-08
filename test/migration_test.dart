import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/database.dart';

/// A no-op migration strategy: blocks drift's automatic table creation so
/// the test can build an "old schema" database first, then run upgrades.
class _NoopMigration extends MigrationStrategy {
  _NoopMigration() : super(onCreate: (_) async {}, onUpgrade: (m, f, t) async {});
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('schemaVersion = 4', () {
    expect(db.schemaVersion, 4);
  });

  test('v4 schema: records has v0.1.1 columns + allDay + reminderOffsets',
      () async {
    final info = await db.customSelect('PRAGMA table_info(records)').get();
    final cols = info.map((r) => r.data['name'] as String).toSet();
    expect(cols, containsAll([
      'start_at',
      'end_at',
      'next_instance_id',
      'all_day', // v0.1.2 F2b
      'reminder_offsets', // v0.1.3 L2
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
    // allDay defaults to true (all-day), non-null.
    expect(row.allDay, isTrue);
  });

  test('v1->v3: full chain upgrade from v1 adds all columns, data intact',
      () async {
    final raw = NativeDatabase.memory();
    final v1 = AppDatabase.forTesting(raw, migrationOverride: _NoopMigration());

    // Build the v1-shaped records table (no v0.1.1 columns, no all_day)
    // and seed one legacy row.
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

    // Real upgrade chain: from=1 up to the current version in steps.
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
    expect(rows.first.allDay, isTrue,
        reason: 'v1 row has no due_at -> backfilled all-day');
    await v1.close();
  });

  test('v2->v3: allDay added and backfilled via midnight sentinel',
      () async {
    final raw = NativeDatabase.memory();
    final v2 = AppDatabase.forTesting(raw, migrationOverride: _NoopMigration());

    // Build the v2-shaped records table (v0.1.1 columns, no all_day).
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
    // drift stores DateTime as unix seconds (integer).
    final tZero = DateTime(2026, 9, 4).millisecondsSinceEpoch ~/ 1000; // midnight
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

    // all_day exists in the physical schema.
    final cols = await v2.customSelect('PRAGMA table_info(records)').get();
    final names = cols.map((r) => r.data['name'] as String).toSet();
    expect(names, contains('all_day'));

    // Backfill semantics: midnight -> all-day; timed -> not all-day;
    // no due -> all-day.
    final rows = await v2.select(v2.records).get();
    final byId = {for (final r in rows) r.id: r};
    expect(byId['v2-allday']!.allDay, isTrue, reason: 'v2 midnight sentinel -> all-day');
    expect(byId['v2-withtime']!.allDay, isFalse, reason: 'v2 with time-of-day -> not all-day');
    expect(byId['v2-nodue']!.allDay, isTrue, reason: 'no due -> all-day');
    await v2.close();
  });

  test('v3->v4: reminderOffsets column added, existing rows null', () async {
    final raw = NativeDatabase.memory();
    final v3 = AppDatabase.forTesting(raw, migrationOverride: _NoopMigration());

    // Build the v3-shaped records table (no reminder_offsets).
    await v3.customStatement('''
      CREATE TABLE records (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL DEFAULT '',
        list_id TEXT NULL,
        pinned INTEGER NOT NULL DEFAULT 0,
        all_day INTEGER NOT NULL DEFAULT 1,
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
    await v3.customStatement('''
      INSERT INTO records (id, title, body, pinned, created_at, updated_at)
      VALUES ('v3row', 'legacy', '', 0, 1756900000000, 1756900000000)
    ''');

    final m = v3.createMigrator();
    await v3.migrateV3ToV4(m, 3, 4);

    final cols = await v3.customSelect('PRAGMA table_info(records)').get();
    final names = cols.map((r) => r.data['name'] as String).toSet();
    expect(names, contains('reminder_offsets'));

    final rows = await v3.select(v3.records).get();
    expect(rows, hasLength(1));
    expect(rows.first.reminderOffsets, isNull,
        reason: 'pre-v4 rows have no reminders');
    await v3.close();
  });
}
