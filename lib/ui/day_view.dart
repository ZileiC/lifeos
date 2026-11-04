import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/task_repository.dart';
import 'day_grid.dart';

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
          child: DayGrid(
            day: day,
            slices: slices,
            isToday: isToday,
            now: DateTime.now(),
            onEditSlice: onEditSlice,
          ),
        ),
      ],
    );
  }
}
