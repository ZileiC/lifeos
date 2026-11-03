import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/task_colors.dart';
import '../data/task_repository.dart';

String _weekdayShort(int day) =>
    const ['一', '二', '三', '四', '五', '六', '日'][day - 1];

class DayView extends StatelessWidget {
  const DayView({
    super.key,
    required this.day,
    required this.slices,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onAddTask,
    required this.onEditSlice,
  });

  final DateTime day;
  final List<DaySliceWithTask> slices;
  final bool isToday;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onAddTask;
  final ValueChanged<DaySliceWithTask> onEditSlice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    DaySliceWithTask? current;
    DaySliceWithTask? next;
    if (isToday) {
      final now = DateTime.now();
      for (final entry in slices) {
        if (!entry.slice.startAt.isAfter(now) &&
            entry.slice.endAt.isAfter(now)) {
          current = entry;
        }
        if (entry.slice.startAt.isAfter(now) && next == null) {
          next = entry;
        }
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          child: Row(
            children: [
              IconButton(
                key: const Key('day-prev'),
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${DateFormat('M月d日').format(day)} 周${_weekdayShort(day.weekday)}',
                      style: theme.textTheme.titleMedium,
                    ),
                    if (!isToday)
                      TextButton(
                        key: const Key('day-today'),
                        onPressed: onToday,
                        child: const Text('回到今天'),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                key: const Key('day-add-task'),
                onPressed: onAddTask,
                icon: const Icon(Icons.add_task),
                label: const Text('排任务'),
              ),
              IconButton(
                key: const Key('day-next'),
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: slices.isEmpty
              ? Center(
                  child: Text(
                    '把任务排到今天',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: slices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = slices[index];
                    final color =
                        Color(TaskColors.resolve(entry.task.color, entry.task.id));
                    final isCurrent = identical(entry, current);
                    final isNext = identical(entry, next);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: Key('slice-${entry.slice.id}'),
                        onTap: () => onEditSlice(entry),
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
                              SizedBox(
                                width: 92,
                                child: Text(
                                  '${DateFormat('HH:mm').format(entry.slice.startAt)}'
                                  '–${DateFormat('HH:mm').format(entry.slice.endAt)}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  entry.task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                              if (isCurrent)
                                const _Badge(text: '当前')
                              else if (isNext)
                                const _Badge(text: '下一块'),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}
