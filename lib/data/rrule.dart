/// 简单循环规则（MVP 默认模式）。
///
/// 字符串编码，便于存库与将来向 RFC5545 RRULE 升级：
/// - `daily`            每天
/// - `weekly:<1-7>`     每周 X（1=周一 … 7=周日）
/// - `monthly:<1-31>`   每月 X 日
/// - `every:<n>days`    间隔 N 天
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
    return null; // 不认识的编码当作不循环，宁可不生成也不崩
  }

  /// 基准日（通常是到期日或完成日）之后的下一次发生。
  /// 每周X：直接对齐到目标星期；每月X日：同月未过用同月，否则下月（月末截断）。
  DateTime nextAfter(DateTime base) {
    final d = DateTime(base.year, base.month, base.day);
    switch (code) {
      case 'daily':
        return d.add(const Duration(days: 1));
    }
    if (code.startsWith('weekly:')) {
      final target = int.parse(code.substring(7)); // 1=周一
      final current = d.weekday; // Dart: 1=周一…7=周日，正好一致
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

  /// UI 用中文描述
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

  /// 下拉选择器用的候选规则
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
