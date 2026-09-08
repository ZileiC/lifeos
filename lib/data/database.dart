import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Lists, Records, Checkitems])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : _migrationOverride = null, super(_openConnection());

  /// 测试用：注入自定义 QueryExecutor（内存库等）。
  /// [migrationOverride] 可替换迁移策略（migration 测试用它阻止自动建表）。
  // 本构造器因私有字段名与参数名不一致，无法用 super/init-formal 语法，
  // 两条 lint 在文件级豁免（仅此一处使用）。
  // ignore_for_file: use_super_parameters, prefer_initializing_formals
  AppDatabase.forTesting(QueryExecutor e, {MigrationStrategy? migrationOverride})
      : _migrationOverride = migrationOverride,
        super(e);

  final MigrationStrategy? _migrationOverride;

  @override
  int get schemaVersion => 3; // v3: records 加 allDay（v0.1.2 F2b 全天标记）

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'lifeos',
      native: const DriftNativeOptions(
        // Android 用应用文档目录；Windows 用 %APPDATA%/LifeOS
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
        },
      );

  /// v1 -> v2 升级步骤（独立成方法便于迁移测试直接驱动）：
  /// records 加 startAt/endAt（v0.1.1 F1 时间区间）
  ///        + nextInstanceId（v0.1.1 F3 循环实例血缘指针）
  Future<void> migrateV1ToV2(Migrator m, int from, int to) async {
    if (from < 2) {
      await m.addColumn(records, records.startAt);
      await m.addColumn(records, records.endAt);
      await m.addColumn(records, records.nextInstanceId);
    }
  }

  /// v2 -> v3 升级步骤（v0.1.2 F2b）：
  /// records 加 allDay 显式全天标记。
  /// 存量数据回填：v0.1.1 时代「零点=仅日期」，故 dueAt 时刻为零点的行回填
  /// allDay=true；带真实时刻的行回填 allDay=false。零点哨兵从此废除——
  /// 用户显式选 00:00 时是真实 00:00（allDay=false）。
  Future<void> migrateV2ToV3(Migrator m, int from, int to) async {
    if (from < 3) {
      await m.addColumn(records, records.allDay);
      // 回填 v0.1.1 的零点哨兵：非零时刻 → 非全天；零点/空 → 全天。
      // due_at 存的是 unix 秒（drift 默认）。strftime(..., 'unixepoch') 按 UTC
      // 解释会把本地零点算成前一天 16:00（UTC+8），必须叠加本地时区偏移——
      // drift 写入时用的是本地时间→unix 秒，读回也用本地解释。
      // 'localtime' 修饰符把 unix 秒换算到本地时区，与 drift 语义一致。
      await customStatement(
        'UPDATE records SET all_day = CASE '
        'WHEN due_at IS NOT NULL '
        "AND (strftime('%H:%M:%S', due_at, 'unixepoch', 'localtime') != '00:00:00') "
        'THEN 0 ELSE 1 END',
      );
    }
  }
}

/// 删除目录探测（Windows 端调试确认库文件落位）
Future<Directory> dbFolder() => getApplicationDocumentsDirectory();
