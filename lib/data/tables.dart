import 'package:drift/drift.dart';

/// List (project/category) table.
/// DataClassName is explicit: Drift would otherwise strip the trailing "s"
/// and name the row class `List`, shadowing dart:core's List.
@DataClassName('ListRecord')
class Lists extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get icon => text().nullable()(); // icon key, reserved for future
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()(); // tombstone

  @override
  Set<Column> get primaryKey => {id};
}

/// Record: todo + lightweight note hybrid.
class Records extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get listId => text().nullable()(); // null = inbox
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  // v0.1.2 (F2b): due date-time + explicit all-day flag. The "midnight means
  // date-only" sentinel is gone; allDay=true means user explicitly picked
  // all-day, false means dueAt carries a real time-of-day.
  BoolColumn get allDay => boolean().withDefault(const Constant(true))();
  DateTimeColumn get dueAt => dateTime().nullable()();
  // Time span (F1): start/end, orthogonal to dueAt and rrule.
  // F1c: full timestamps (may span days); no implicit anchoring.
  DateTimeColumn get startAt => dateTime().nullable()();
  DateTimeColumn get endAt => dateTime().nullable()();
  TextColumn get rrule => text().nullable()(); // simple recurrence, see RRule
  // v0.1.1 (F3): UUID of the "next instance" spawned when a recurring record
  // completes. Used on undo-completion to reclaim a pure-clone instance.
  TextColumn get nextInstanceId => text().nullable()();
  // v0.1.3 (L2): reminder lead times as a comma-separated list of minutes
  // (e.g. "0,15,60"); 0 = on-time. Empty/null = no reminder. Multi-select
  // (rationale in WORKLOG 2026-09-08).
  TextColumn get reminderOffsets => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()(); // tombstone

  @override
  Set<Column> get primaryKey => {id};
}

/// Checkitem: 0..N per record.
/// Note: the column must NOT be named `text` — that collides with Drift's
/// text() column builder and breaks the generator (recursive resolution).
class Checkitems extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get recordId => text()();
  TextColumn get content => text().withLength(min: 1, max: 1000)();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()(); // tombstone

  @override
  Set<Column> get primaryKey => {id};
}
