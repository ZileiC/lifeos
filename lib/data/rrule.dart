/// Simple recurrence rules (MVP default mode).
///
/// String encoding keeps storage trivial and leaves headroom for a future
/// upgrade to full RFC5545 RRULE:
/// - `daily`
/// - `weekly:<1-7>`     (1=Mon .. 7=Sun)
/// - `monthly:<1-31>`
/// - `every:<n>days`
class RRule {
  const RRule.daily() : code = 'daily';
  const RRule.weekly(int weekday) : code = 'weekly:$weekday';
  const RRule.monthly(int day) : code = 'monthly:$day';
  const RRule.everyDays(int n) : code = 'every:${n}days';

  final String code;

  static RRule? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw == 'daily') return const RRule.daily();
    if (raw.startsWith('weekly:')) {
      final w = int.tryParse(raw.substring(7));
      if (w == null || w < 1 || w > 7) return null;
      return RRule.weekly(w);
    }
    if (raw.startsWith('monthly:')) {
      final d = int.tryParse(raw.substring(8));
      if (d == null || d < 1 || d > 31) return null;
      return RRule.monthly(d);
    }
    if (raw.startsWith('every:') && raw.endsWith('days')) {
      final n = int.tryParse(raw.substring(6, raw.length - 4));
      if (n == null || n < 1) return null;
      return RRule.everyDays(n);
    }
    return null; // unknown codes mean "not recurring" — never crash on parse
  }

  /// Next occurrence after [base] (usually the due or completion date).
  /// weekly: aligns to the target weekday; monthly: same month if not yet
  /// passed, otherwise next month (clamped to the month end).
  DateTime nextAfter(DateTime base) {
    final d = DateTime(base.year, base.month, base.day);
    switch (code) {
      case 'daily':
        return d.add(const Duration(days: 1));
    }
    if (code.startsWith('weekly:')) {
      final target = int.parse(code.substring(7)); // 1=Mon
      final current = d.weekday; // Dart: 1=Mon..7=Sun, matches our encoding
      final diff = (target - current) % 7;
      return d.add(Duration(days: diff == 0 ? 7 : diff));
    }
    if (code.startsWith('monthly:')) {
      final target = int.parse(code.substring(8));
      var y = d.year;
      var m = d.month;
      var day = target;
      if (day > _daysInMonth(y, m) || day <= d.day) {
        m++;
        if (m > 12) {
          m = 1;
          y++;
        }
        day = target.clamp(1, _daysInMonth(y, m));
      }
      return DateTime(y, m, day);
    }
    if (code.startsWith('every:')) {
      final n = int.parse(code.substring(6, code.length - 4));
      return d.add(Duration(days: n));
    }
    return d.add(const Duration(days: 1));
  }

  static int _daysInMonth(int y, int m) {
    if (m == 2) return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28;
    const k = [31, 0, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return k[m - 1];
  }

  /// Chinese label for the UI.
  String get label {
    switch (code) {
      case 'daily':
        return '每天';
    }
    if (code.startsWith('weekly:')) {
      return '每周${'一二三四五六日'[int.parse(code.substring(7)) - 1]}';
    }
    if (code.startsWith('monthly:')) {
      return '每月${int.parse(code.substring(8))}日';
    }
    if (code.startsWith('every:')) {
      return '每 ${int.parse(code.substring(6, code.length - 4))} 天';
    }
    return code;
  }

  /// Candidate rules for the picker sheet.
  static List<RRule> get presets => const [
        RRule.daily(),
        RRule.weekly(1),
        RRule.weekly(2),
        RRule.weekly(3),
        RRule.weekly(4),
        RRule.weekly(5),
        RRule.weekly(6),
        RRule.weekly(7),
        RRule.everyDays(2),
        RRule.everyDays(3),
        RRule.everyDays(7),
        RRule.everyDays(14),
      ];
}
