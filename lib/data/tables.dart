import 'package:drift/drift.dart';

/// 清单（项目/分类）
/// DataClassName 显式命名：Drift 默认会去掉表名末尾 s，把行类命名为 `List`
/// 直接遮蔽 dart:core 的 List，必须改名。
@DataClassName('ListRecord')
class Lists extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get icon => text().nullable()(); // 图标标识，留扩展
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 记录：待办 + 轻笔记混合
class Records extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get body => text().withDefault(const Constant(''))(); // 轻笔记正文
  TextColumn get listId => text().nullable()(); // 所属清单，可空=收件箱
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  // v0.1.2（F2b）：到期日期-时间 + 全天标记（显式字段，废弃「零点=仅日期」哨兵）。
  // allDay=true 表示用户显式选择全天任务；false 表示 dueAt 携带真实时刻。
  BoolColumn get allDay => boolean().withDefault(const Constant(true))();
  DateTimeColumn get dueAt => dateTime().nullable()(); // 到期/今天归属，可带时刻
  // 时间区间（F1）：开始–结束时刻，与 dueAt/rrule 正交。
  // 约定：日期部分无意义（跟随 dueAt 的日期；无 dueAt 时视为当天），只用时刻部分。
  DateTimeColumn get startAt => dateTime().nullable()();
  DateTimeColumn get endAt => dateTime().nullable()();
  TextColumn get rrule => text().nullable()(); // 简单循环规则，见 RRule
  // v0.1.1（F3）：完成循环任务时生成的下一次实例的 UUID（血缘指针）。
  // 撤销完成时用于定位并回收「未被编辑过」的下一次实例；非循环任务恒空。
  TextColumn get nextInstanceId => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()(); // 墓碑

  @override
  Set<Column> get primaryKey => {id};
}

/// 勾选项：一条记录挂 0~N 个
/// 注意：列名不能用 `text`，会与 Drift 构建方法 text() 递归冲突
class Checkitems extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get recordId => text()();
  TextColumn get content => text().withLength(min: 1, max: 1000)();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
