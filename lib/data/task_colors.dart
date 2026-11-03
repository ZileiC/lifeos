/// Stable task-level colors.
///
/// A task owns one color for its whole life; every day slice of that task uses
/// the same color. The color is derived deterministically from the task id when
/// no explicit color has been persisted yet (legacy rows).
class TaskColors {
  const TaskColors._();

  /// Muted palette that reads well on the dark theme.
  static const List<int> palette = <int>[
    0xFF7FA7C9, // blue
    0xFF8FBFA8, // green
    0xFFD9B36C, // amber
    0xFFC98A8A, // rose
    0xFF9B8FC4, // violet
    0xFF6FB7B7, // teal
    0xFFC4A484, // brown
    0xFFA8B56F, // olive
    0xFFB78FB0, // mauve
    0xFF8E9EC4, // slate
  ];

  static int forId(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  /// Returns the persisted color, or the deterministic fallback.
  static int resolve(int? color, String id) => color ?? forId(id);
}
