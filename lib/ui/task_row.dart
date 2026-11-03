import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/recurrence.dart';
import '../data/task_colors.dart';
import '../data/task_math.dart';

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
    return '每周$daysText · 每次 ${task.estimatedMinutes ?? '—'} 分钟';
  }
  final estimate = task.estimatedMinutes;
  if (remaining == null) return '预估 ${estimate ?? '—'} 分钟';
  return '剩余 $remaining / 预估 $estimate 分钟';
}

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

    return Material(
      color: selected ? theme.colorScheme.surfaceContainerHighest : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (task.pinned)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.push_pin, size: 14),
                          ),
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$due · $plan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'U${task.urgency ?? '—'}  I${task.importance ?? '—'}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (selectionMode) ...[
                const SizedBox(width: 6),
                Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
