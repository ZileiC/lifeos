/// Reminder lead-time presets and computation (v0.1.3 L2).
///
/// An offset is minutes before the DDL; 0 means "on time".
/// Multi-select: users commonly pair a heads-up ("1 hour before") with a
/// last-call ("15 minutes before"); single-select would force a choice.
/// Stored as a comma-separated minute list in `records.reminderOffsets`.
library;

/// All selectable presets, in display order.
const List<int> kReminderOffsetPresets = [0, 5, 15, 30, 60, 120, 1440];

/// Parse the stored column value into a sorted, de-duplicated offset list.
/// Null/empty/invalid entries yield an empty list (no reminders).
List<int> parseReminderOffsets(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final parsed = raw
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .where((m) => m >= 0)
      .toSet()
      .toList()
    ..sort();
  return parsed;
}

/// Encode offsets for storage (sorted, de-duplicated, comma-separated).
/// Empty input -> null (column stays null = no reminder).
String? encodeReminderOffsets(List<int> offsets) {
  final clean = offsets.toSet().toList()..sort();
  if (clean.isEmpty) return null;
  return clean.join(',');
}

/// Compute all trigger instants for a record's DDL.
///
/// All-day tasks have no meaningful "on time" instant at midnight, so the
/// default trigger is 09:00 of the due day (self-explanatory label in the UI);
/// offsets other than 0 are subtracted from that 09:00 anchor, e.g. a
/// "1 day before" pick on an all-day task due 9/10 fires at 9/9 09:00.
///
/// Returns one instant per distinct offset; triggers already in the past are
/// dropped (no barrage of stale notifications after editing an old record).
List<DateTime> computeReminderInstants({
  required DateTime? dueAt,
  required bool allDay,
  required List<int> offsets,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  if (dueAt == null || offsets.isEmpty) return const [];

  final DateTime anchor;
  if (allDay) {
    final day = DateTime(dueAt.year, dueAt.month, dueAt.day);
    anchor = day.add(const Duration(hours: 9)); // 09:00 default for all-day
  } else {
    anchor = dueAt;
  }

  final instants = <DateTime>{};
  for (final minutes in offsets) {
    final t = anchor.subtract(Duration(minutes: minutes));
    if (t.isAfter(at)) instants.add(t);
  }
  return instants.toList()..sort();
}
