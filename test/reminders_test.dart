import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/reminders.dart';

void main() {
  group('parseReminderOffsets', () {
    test('null/empty/blank -> empty list', () {
      expect(parseReminderOffsets(null), isEmpty);
      expect(parseReminderOffsets(''), isEmpty);
      expect(parseReminderOffsets('  '), isEmpty);
    });

    test('comma list parses, sorts, de-duplicates', () {
      expect(parseReminderOffsets('60,0,15,15'), [0, 15, 60]);
    });

    test('invalid entries dropped, negatives dropped', () {
      expect(parseReminderOffsets('abc,-5,15'), [15]);
    });
  });

  group('encodeReminderOffsets', () {
    test('round-trips with parse', () {
      final encoded = encodeReminderOffsets([60, 0, 15]);
      expect(encoded, '0,15,60');
      expect(parseReminderOffsets(encoded), [0, 15, 60]);
    });

    test('empty list -> null (no reminder)', () {
      expect(encodeReminderOffsets(const []), isNull);
    });
  });

  group('computeReminderInstants (L2 acceptance core)', () {
    final now = DateTime(2026, 9, 8, 10, 0);

    test('timed task: each offset subtracts from DDL', () {
      final due = DateTime(2026, 9, 8, 14, 30);
      final instants = computeReminderInstants(
        dueAt: due,
        allDay: false,
        offsets: [0, 15, 60],
        now: now,
      );
      expect(instants, [
        DateTime(2026, 9, 8, 13, 30), // 60 min before
        DateTime(2026, 9, 8, 14, 15), // 15 min before
        DateTime(2026, 9, 8, 14, 30), // on time
      ]);
    });

    test('all-day task: 09:00 anchor on the due day', () {
      final due = DateTime(2026, 9, 10); // all-day -> stored midnight
      final instants = computeReminderInstants(
        dueAt: due,
        allDay: true,
        offsets: [0, 60],
        now: now,
      );
      expect(instants, [
        DateTime(2026, 9, 10, 8, 0), // 09:00 minus 60
        DateTime(2026, 9, 10, 9, 0), // 09:00 anchor
      ]);
    });

    test('past triggers dropped (no stale barrage after editing)', () {
      final due = DateTime(2026, 9, 8, 10, 30); // 30 min from "now"
      final instants = computeReminderInstants(
        dueAt: due,
        allDay: false,
        offsets: [60, 15], // 60-before is already past
        now: now,
      );
      expect(instants, [DateTime(2026, 9, 8, 10, 15)]);
    });

    test('null dueAt or empty offsets -> empty', () {
      expect(
        computeReminderInstants(
            dueAt: null, allDay: false, offsets: [15], now: now),
        isEmpty,
      );
      expect(
        computeReminderInstants(
            dueAt: DateTime(2026, 9, 9), allDay: true, offsets: [], now: now),
        isEmpty,
      );
    });

    test('acceptance scenario: DDL in 2 min, 1 min lead -> fires in 1 min',
        () {
      final due = now.add(const Duration(minutes: 2));
      final instants = computeReminderInstants(
        dueAt: due,
        allDay: false,
        offsets: [1], // the acceptance lead (custom value, 1 minute)
        now: now,
      );
      expect(instants, [due.subtract(const Duration(minutes: 1))]);
      expect(instants.first.difference(now), const Duration(minutes: 1));
    });
  });
}
