import '../data/database.dart';
import '../data/task_repository.dart';
import 'ai_models.dart';

/// Validates an [AiPlan] against the local data. Semantic errors (unknown task,
/// bad time, cross-day, past) drop the slice; soft problems (overlap,
/// over-allocation) keep the slice as a warning. Nothing is written here.
class PlanValidator {
  const PlanValidator({
    required this.tasks,
    required this.existingSlices,
    required this.targetDay,
    required this.now,
  });

  final List<Record> tasks;

  /// Target-day slices plus the next 7 days (for load/over-allocation checks).
  final List<DaySliceWithTask> existingSlices;
  final DateTime targetDay;
  final DateTime now;

  PlanValidation validate(AiPlan plan) {
    final taskById = <String, Record>{for (final task in tasks) task.id: task};
    final targetExisting = existingSlices
        .where((item) => _sameDay(item.slice.startAt, targetDay))
        .toList();
    final issues = <PlanIssue>[];
    final valid = <AiSliceSuggestion>[];

    for (var index = 0; index < plan.slices.length; index++) {
      final slice = plan.slices[index];
      final task = taskById[slice.taskId];

      if (task == null) {
        issues.add(PlanIssue(
          index: index,
          kind: PlanIssueKind.unknownTask,
          severity: PlanIssueSeverity.error,
          message: '任务不存在：${slice.taskId}（AI 不能发明任务）',
        ));
        continue;
      }
      if (!slice.endAt.isAfter(slice.startAt)) {
        issues.add(PlanIssue(
          index: index,
          kind: PlanIssueKind.invalidTime,
          severity: PlanIssueSeverity.error,
          message: '时间非法：结束必须晚于开始',
        ));
        continue;
      }
      if (!_sameDay(slice.startAt, targetDay) ||
          !_sameDay(slice.endAt, targetDay)) {
        issues.add(PlanIssue(
          index: index,
          kind: PlanIssueKind.crossDay,
          severity: PlanIssueSeverity.error,
          message: '跨天建议不支持：时间块必须在目标日内',
        ));
        continue;
      }
      if (_sameDay(targetDay, now) &&
          slice.startAt.isBefore(now.subtract(const Duration(minutes: 5)))) {
        issues.add(PlanIssue(
          index: index,
          kind: PlanIssueKind.past,
          severity: PlanIssueSeverity.error,
          message: '不能把时间块排到已经过去的时间',
        ));
        continue;
      }

      final overlapsExisting = targetExisting
          .any((item) => _overlapsRange(item.slice.startAt, item.slice.endAt,
              slice.startAt, slice.endAt));
      final overlapsSuggested = valid.any((other) => _overlapsRange(
          other.startAt, other.endAt, slice.startAt, slice.endAt));
      if (overlapsExisting || overlapsSuggested) {
        issues.add(PlanIssue(
          index: index,
          kind: PlanIssueKind.overlap,
          severity: PlanIssueSeverity.warning,
          message: '与已有安排重叠，确认前请调整',
        ));
      }

      final estimate = task.estimatedMinutes;
      if (task.recurrence == null && estimate != null) {
        final existingMinutes = existingSlices
            .where((item) => item.slice.taskId == task.id)
            .fold<int>(
                0,
                (sum, item) =>
                    sum + item.slice.endAt.difference(item.slice.startAt).inMinutes);
        final suggestedMinutes = valid
                .where((item) => item.taskId == task.id)
                .fold<int>(0, (sum, item) => sum + item.duration.inMinutes) +
            slice.duration.inMinutes;
        if (existingMinutes + suggestedMinutes > estimate) {
          issues.add(PlanIssue(
            index: index,
            kind: PlanIssueKind.overAllocation,
            severity: PlanIssueSeverity.warning,
            message: '超过任务剩余预估（${existingMinutes + suggestedMinutes}m > ${estimate}m）',
          ));
        }
      }

      valid.add(slice);
    }

    return PlanValidation(validSlices: valid, issues: issues);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _overlapsRange(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) =>
      aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
}
