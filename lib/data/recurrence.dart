import 'dart:convert';

/// Weekly-fixed task rule: on the selected weekdays, at [startMinutes], for
/// [durationMinutes], between [fromDate] and [toDate] (both inclusive).
///
/// Stored as JSON in records.recurrence. Deliberately not a full RFC 5545
/// RRULE: Stage 0 only needs a weekly timetable with a date range.
class RecurrenceSpec {
  const RecurrenceSpec({
    required this.weekdays,
    required this.startMinutes,
    required this.durationMinutes,
    required this.fromDate,
    required this.toDate,
  });

  /// Hard caps so a bad range cannot create an unbounded number of slices.
  static const int maxDays = 366;
  static const int maxSlices = 500;

  final Set<int> weekdays; // 1=Monday .. 7=Sunday
  final int startMinutes; // minute of day, 0..1439
  final int durationMinutes;
  final DateTime fromDate;
  final DateTime toDate;

  bool get isValid {
    return weekdays.isNotEmpty &&
        weekdays.every((day) => day >= 1 && day <= 7) &&
        startMinutes >= 0 &&
        startMinutes < 1440 &&
        durationMinutes > 0 &&
        durationMinutes <= 1440 &&
        !_dateOnly(toDate).isBefore(_dateOnly(fromDate));
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'weekdays': (weekdays.toList()..sort()),
        'startMinutes': startMinutes,
        'durationMinutes': durationMinutes,
        'fromDate': _formatDate(fromDate),
        'toDate': _formatDate(toDate),
      };

  String encode() => jsonEncode(toJson());

  static RecurrenceSpec? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final rawDays = decoded['weekdays'];
      if (rawDays is! List) return null;
      final days = rawDays.whereType<int>().toSet();
      final start = decoded['startMinutes'];
      final duration = decoded['durationMinutes'];
      final from = DateTime.tryParse(decoded['fromDate'] as String? ?? '');
      final to = DateTime.tryParse(decoded['toDate'] as String? ?? '');
      if (start is! int || duration is! int || from == null || to == null) {
        return null;
      }
      final spec = RecurrenceSpec(
        weekdays: days,
        startMinutes: start,
        durationMinutes: duration,
        fromDate: from,
        toDate: to,
      );
      return spec.isValid ? spec : null;
    } catch (_) {
      return null;
    }
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }
}

class RecurrenceOccurrence {
  const RecurrenceOccurrence({required this.startAt, required this.endAt});

  final DateTime startAt;
  final DateTime endAt;
}

class RecurrencePlanner {
  const RecurrencePlanner._();

  /// Expands a valid spec into occurrences, capped by maxDays/maxSlices.
  static List<RecurrenceOccurrence> occurrences(RecurrenceSpec spec) {
    if (!spec.isValid) return const <RecurrenceOccurrence>[];
    final first = RecurrenceSpec._dateOnly(spec.fromDate);
    final lastRequested = RecurrenceSpec._dateOnly(spec.toDate);
    final lastAllowed =
        first.add(const Duration(days: RecurrenceSpec.maxDays - 1));
    final last = lastRequested.isAfter(lastAllowed) ? lastAllowed : lastRequested;

    final result = <RecurrenceOccurrence>[];
    var day = first;
    while (!day.isAfter(last)) {
      if (spec.weekdays.contains(day.weekday)) {
        final startAt = day.add(Duration(minutes: spec.startMinutes));
        final endAt = startAt.add(Duration(minutes: spec.durationMinutes));
        result.add(RecurrenceOccurrence(startAt: startAt, endAt: endAt));
        if (result.length >= RecurrenceSpec.maxSlices) break;
      }
      day = day.add(const Duration(days: 1));
    }
    return result;
  }
}
