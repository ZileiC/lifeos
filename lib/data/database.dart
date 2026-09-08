import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Lists, Records, Checkitems])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : _migrationOverride = null, super(_openConnection());

  /// Testing constructor: inject a custom QueryExecutor (in-memory db etc).
  /// [migrationOverride] swaps the migration strategy (the migration tests use
  /// it to block automatic table creation).
  // This constructor cannot use super/init-formal syntax because the private
  // field name differs from the parameter name; lint exemptions are
  // file-scoped (single use site).
  // ignore_for_file: use_super_parameters, prefer_initializing_formals
  AppDatabase.forTesting(QueryExecutor e, {MigrationStrategy? migrationOverride})
      : _migrationOverride = migrationOverride,
        super(e);

  final MigrationStrategy? _migrationOverride;

  @override
  int get schemaVersion => 4; // v4: records.reminderOffsets (v0.1.3 L2)

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'lifeos',
      native: const DriftNativeOptions(
        // Android: app documents dir; Windows: %APPDATA%/LifeOS
        databaseDirectory: getApplicationDocumentsDirectory,
      ),
    );
  }

  @override
  MigrationStrategy get migration => _migrationOverride ?? _defaultMigration;

  MigrationStrategy get _defaultMigration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          await migrateV1ToV2(m, from, to);
          await migrateV2ToV3(m, from, to);
          await migrateV3ToV4(m, from, to);
        },
      );

  /// v1 -> v2 (v0.1.1 F1/F3): records adds startAt/endAt (time span) and
  /// nextInstanceId (lineage pointer to the next recurring instance).
  Future<void> migrateV1ToV2(Migrator m, int from, int to) async {
    if (from < 2) {
      await m.addColumn(records, records.startAt);
      await m.addColumn(records, records.endAt);
      await m.addColumn(records, records.nextInstanceId);
    }
  }

  /// v2 -> v3 (v0.1.2 F2b): records adds the explicit allDay flag.
  /// Backfill for the v0.1.1 "midnight = date-only" sentinel: rows with a
  /// non-midnight dueAt become allDay=false; midnight/null become allDay=true.
  /// The sentinel is gone — an explicit 00:00 pick is now a real 00:00 with
  /// allDay=false.
  Future<void> migrateV2ToV3(Migrator m, int from, int to) async {
    if (from < 3) {
      await m.addColumn(records, records.allDay);
      // due_at is stored as unix seconds (drift default). strftime with
      // 'unixepoch' interprets it as UTC, which turns a local (UTC+8) midnight
      // into the previous day 16:00; the 'localtime' modifier converts it back
      // to drift's local-time semantics.
      await customStatement(
        'UPDATE records SET all_day = CASE '
        'WHEN due_at IS NOT NULL '
        "AND (strftime('%H:%M:%S', due_at, 'unixepoch', 'localtime') != '00:00:00') "
        'THEN 0 ELSE 1 END',
      );
    }
  }

  /// v3 -> v4 (v0.1.3 L2): records adds reminderOffsets (comma-separated
  /// minute offsets, e.g. "0,15,60"). Null = no reminder for existing rows.
  Future<void> migrateV3ToV4(Migrator m, int from, int to) async {
    if (from < 4) {
      await m.addColumn(records, records.reminderOffsets);
    }
  }
}

/// Debug helper to locate the database directory on Windows.
Future<Directory> dbFolder() => getApplicationDocumentsDirectory();
