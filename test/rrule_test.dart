import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/data/rrule.dart';

void main() {
  group('RRule.parse', () {
    test('null/空/未知编码返回 null', () {
      expect(RRule.parse(null), isNull);
      expect(RRule.parse(''), isNull);
      expect(RRule.parse('bogus'), isNull);
      expect(RRule.parse('weekly:9'), isNull);
      expect(RRule.parse('monthly:0'), isNull);
    });

    test('四种模式解析', () {
      expect(RRule.parse('daily'), isA<RRule>());
      expect(RRule.parse('weekly:3'), isA<RRule>());
      expect(RRule.parse('monthly:15'), isA<RRule>());
      expect(RRule.parse('every:7days'), isA<RRule>());
    });
  });

  group('RRule.nextAfter', () {
    // 2026-09-04 is a Friday.
    final fri = DateTime(2026, 9, 4);

    test('daily：次日', () {
      expect(RRule.daily().nextAfter(fri), DateTime(2026, 9, 5));
    });

    test('weekly：本周已过则下周', () {
      // Friday -> weekly Monday: next Monday is 9-7.
      expect(RRule.weekly(1).nextAfter(fri), DateTime(2026, 9, 7));
      // Friday -> weekly Friday: next Friday is 9-11.
      expect(RRule.weekly(5).nextAfter(fri), DateTime(2026, 9, 11));
      // Friday -> weekly Sunday: 9-6.
      expect(RRule.weekly(7).nextAfter(fri), DateTime(2026, 9, 6));
    });

    test('monthly：本月未过用本月，过了用下月', () {
      // 9-4 -> monthly 15th: 9-15.
      expect(RRule.monthly(15).nextAfter(fri), DateTime(2026, 9, 15));
      // 9-4 -> monthly 4th: 10-4.
      expect(RRule.monthly(4).nextAfter(fri), DateTime(2026, 10, 4));
      // 9-4 -> monthly 31st: September has no 31st -> 10-31.
      expect(RRule.monthly(31).nextAfter(fri), DateTime(2026, 10, 31));
      // 1-31 -> monthly 31st: February has no 31st -> clamp to month end
      // 2-28 (no month skip).
      expect(RRule.monthly(31).nextAfter(DateTime(2026, 1, 31)),
          DateTime(2026, 2, 28));
      // Leap-year February clamps to 29.
      expect(RRule.monthly(31).nextAfter(DateTime(2024, 1, 31)),
          DateTime(2024, 2, 29));
    });

    test('every N days', () {
      expect(RRule.everyDays(3).nextAfter(fri), DateTime(2026, 9, 7));
      expect(RRule.everyDays(14).nextAfter(fri), DateTime(2026, 9, 18));
    });

    test('时间部分被丢弃（归零到日）', () {
      final withTime = DateTime(2026, 9, 4, 15, 30);
      final next = RRule.daily().nextAfter(withTime);
      expect(next, DateTime(2026, 9, 5));
    });
  });

  group('RRule.label', () {
    test('中文描述', () {
      expect(RRule.parse('daily')!.label, '每天');
      expect(RRule.parse('weekly:1')!.label, '每周一');
      expect(RRule.parse('weekly:7')!.label, '每周日');
      expect(RRule.parse('monthly:15')!.label, '每月15日');
      expect(RRule.parse('every:3days')!.label, '每 3 天');
    });
  });
}
