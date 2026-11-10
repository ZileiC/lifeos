import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/recurrence.dart';
import '../data/task_colors.dart';
import '../data/task_math.dart';
import 'theme.dart';

String _weekdayShort(int day) =>
    const ['一', '二', '三', '四', '五', '六', '日'][day - 1];

String _dueLabel(Record task, RecurrenceSpec? recurrence) {
  if (recurrence != null) {
    return '至 ${DateFormat('MM/dd').format(recurrence.toDate)}';
  }
  final due = task.dueAt;
  if (due == null) return '无截止';
  return task.allDay
      ? DateFormat('MM/dd').format(due)
      : DateFormat('MM/dd HH:mm').format(due);
}

String _planLabel(Record task, RecurrenceSpec? recurrence, int? remaining) {
  if (recurrence != null) {
    final days = recurrence.weekdays.toList()..sort();
    final daysText = days.map(_weekdayShort).join('/');
    return '每周$daysText · ${task.estimatedMinutes ?? '—'}min';
  }
  final estimate = task.estimatedMinutes;
  if (remaining == null) return estimate == null ? '无预估' : '预估 $estimate 分钟';
  return '剩余 $remaining / 预估 $estimate 分钟';
}

/// Time-led editorial row: a fixed time gutter, a color dot, the title,
/// and one tabular meta line. No cards, no shadows.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.slices,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Record task;
  final List<DaySlice> slices;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(TaskColors.resolve(task.color, task.id));
    final recurrence = RecurrenceSpec.tryParse(task.recurrence);
    final remaining = TaskMath.remainingMinutes(task, slices);
    final due = _dueLabel(task, recurrence);
    final plan = _planLabel(task, recurrence, remaining);
    final hasSlice = slices.isNotEmpty;
    final startLabel =
        hasSlice ? DateFormat('HH:mm').format(slices.first.startAt) : '--:--';
    final endLabel =
        hasSlice ? DateFormat('HH:mm').format(slices.last.endAt) : '';

    return Material(
      color: selected ? AppTheme.surfaceHigh : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.lineSoft)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      startLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: hasSlice ? AppTheme.ink : AppTheme.inkDim,
                        fontSize: 12,
                      ),
                    ),
                    if (hasSlice)
                      Text(
                        endLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.inkDim,
                          fontSize: 9,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Hero(
                tag: 'task-rail-${task.id}',
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (task.pinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 5),
                            child: Icon(Icons.push_pin,
                                size: 12, color: AppTheme.accentBright),
                          ),
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: AppTheme.ink),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$due · $plan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.inkDim,
                        letterSpacing: 0.01,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'U${task.urgency ?? '—'}  I${task.importance ?? '—'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.inkDim,
                  letterSpacing: 0.04,
                  fontSize: 10,
                ),
              ),
              if (selectionMode) ...[
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: selected ? AppTheme.accentBright : AppTheme.line,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
