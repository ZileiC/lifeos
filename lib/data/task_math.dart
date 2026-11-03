import 'dart:math' as math;

import 'database.dart';

/// Pure task/day-slice arithmetic. No completion state is involved: the phone
/// only knows planned minutes, not done minutes.
class TaskMath {
  const TaskMath._();

  static int plannedMinutes(Iterable<DaySlice> slices) {
    return slices.fold(
      0,
      (sum, slice) => sum + slice.endAt.difference(slice.startAt).inMinutes,
    );
  }

  static bool isRecurring(Record task) => task.recurrence != null;

  /// Normal task: estimate minus planned, floored at zero.
  /// Weekly-fixed task: no cumulative remaining (per-occurrence duration).
  static int? remainingMinutes(Record task, Iterable<DaySlice> slices) {
    if (isRecurring(task)) return null;
    final estimate = task.estimatedMinutes;
    if (estimate == null) return null;
    return math.max(0, estimate - plannedMinutes(slices));
  }

  static bool isOverAllocated(Record task, Iterable<DaySlice> slices) {
    if (isRecurring(task)) return false;
    final estimate = task.estimatedMinutes;
    if (estimate == null) return false;
    return plannedMinutes(slices) > estimate;
  }
}
