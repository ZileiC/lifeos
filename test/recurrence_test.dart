import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/recurrence.dart';

void main() {
  RecurrenceSpec spec({
    Set<int> weekdays = const {1, 3, 5},
    int startMinutes = 540,
    int durationMinutes = 60,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return RecurrenceSpec(
      weekdays: weekdays,
      startMinutes: startMinutes,
      durationMinutes: durationMinutes,
      fromDate: fromDate ?? DateTime(2026, 11, 2),
      toDate: toDate ?? DateTime(2026, 11, 15),
    );
  }

  test('json roundtrip keeps weekdays and dates', () {
    final original = spec();
    final parsed = RecurrenceSpec.tryParse(original.encode());

    expect(parsed, isNotNull);
    expect(parsed!.weekdays, original.weekdays);
    expect(parsed.startMinutes, 540);
    expect(parsed.durationMinutes, 60);
    expect(parsed.fromDate, DateTime(2026, 11, 2));
    expect(parsed.toDate, DateTime(2026, 11, 15));
  });

  test('weekly occurrences on Mon/Wed/Fri', () {
    final occurrences = RecurrencePlanner.occurrences(spec());

    expect(occurrences, hasLength(6));
    expect(occurrences.first.startAt, DateTime(2026, 11, 2, 9));
    expect(occurrences.first.endAt, DateTime(2026, 11, 2, 10));
    expect(occurrences[1].startAt, DateTime(2026, 11, 4, 9));
    expect(occurrences[2].startAt, DateTime(2026, 11, 6, 9));
  });

  test('invalid specs are rejected', () {
    expect(spec(weekdays: {}).isValid, isFalse);
    expect(spec(weekdays: {0}).isValid, isFalse);
    expect(spec(startMinutes: 1440).isValid, isFalse);
    expect(spec(durationMinutes: 0).isValid, isFalse);
    expect(
      spec(
        fromDate: DateTime(2026, 11, 16),
        toDate: DateTime(2026, 11, 2),
      ).isValid,
      isFalse,
    );
    expect(RecurrenceSpec.tryParse('not json'), isNull);
  });

  test('range is capped at 366 days', () {
    final occurrences = RecurrencePlanner.occurrences(spec(
      weekdays: {1, 2, 3, 4, 5, 6, 7},
      fromDate: DateTime(2026, 1, 1),
      toDate: DateTime(2028, 1, 1),
    ));

    expect(occurrences.length, RecurrenceSpec.maxDays);
  });
}
