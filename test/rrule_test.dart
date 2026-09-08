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
    // 2026-09-04 是周五
    final fri = DateTime(2026, 9, 4);

    test('daily：次日', () {
      expect(RRule.daily().nextAfter(fri), DateTime(2026, 9, 5));
    });

    test('weekly：本周已过则下周', () {
      // 周五 -> 每周一：下周一是 9-7
      expect(RRule.weekly(1).nextAfter(fri), DateTime(2026, 9, 7));
      // 周五 -> 每周五：下周五 9-11
      expect(RRule.weekly(5).nextAfter(fri), DateTime(2026, 9, 11));
      // 周五 -> 每周日：9-6
      expect(RRule.weekly(7).nextAfter(fri), DateTime(2026, 9, 6));
    });

    test('monthly：本月未过用本月，过了用下月', () {
      // 9-4 -> 每月 15 日：9-15
      expect(RRule.monthly(15).nextAfter(fri), DateTime(2026, 9, 15));
      // 9-4 -> 每月 4 日：10-4
      expect(RRule.monthly(4).nextAfter(fri), DateTime(2026, 10, 4));
      // 9-4 -> 每月 31 日：9 月没有 31 日 -> 10-31
      expect(RRule.monthly(31).nextAfter(fri), DateTime(2026, 10, 31));
      // 1-31 -> 每月 31 日：2 月没有 31 日 -> 月末截断到 2-28（不跳月）
      expect(RRule.monthly(31).nextAfter(DateTime(2026, 1, 31)),
          DateTime(2026, 2, 28));
      // 闰年 2 月截断到 29
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
