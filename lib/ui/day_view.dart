import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ai/ai_models.dart';
import '../data/database.dart';
import '../data/task_repository.dart';
import 'day_grid.dart';
import 'theme.dart';

String _weekdayShort(int day) =>
    const ['一', '二', '三', '四', '五', '六', '日'][day - 1];

class DayView extends StatefulWidget {
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
    required this.onAiSchedule,
    this.aiLoading = false,
    this.suggested = const <AiSliceSuggestion>[],
    this.suggestedTasks = const <String, Record>{},
  });

  final DateTime day;
  final List<DaySliceWithTask> slices;
  final bool isToday;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onAddTask;
  final ValueChanged<DaySliceWithTask> onEditSlice;
  final VoidCallback onAiSchedule;
  final bool aiLoading;
  final List<AiSliceSuggestion> suggested;
  final Map<String, Record> suggestedTasks;

  @override
  State<DayView> createState() => _DayViewState();
}

class _DayViewState extends State<DayView> {
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0);

  @override
  void dispose() {
    _scrollOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Column(
      children: [
        AnimatedBuilder(
          animation: _scrollOffset,
          builder: (context, child) {
            final t = reduced
                ? 0.0
                : (_scrollOffset.value / 160).clamp(0.0, 1.0);
            return Transform.scale(
              scale: 1 - 0.05 * t,
              alignment: Alignment.centerLeft,
              child: Opacity(opacity: 1 - 0.2 * t, child: child),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.day.day}',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontSize: 30,
                          height: 1,
                        ),
                      ),
                      Text(
                        '${DateFormat('M月').format(widget.day)} · 周${_weekdayShort(widget.day.weekday)}'
                        '${widget.isToday ? ' · 今天' : ''}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppTheme.inkDim,
                          letterSpacing: 0.08,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.isToday)
                  TextButton(
                    key: const Key('day-today'),
                    onPressed: widget.onToday,
                    child: const Text('今天'),
                  ),
                IconButton(
                  key: const Key('day-prev'),
                  tooltip: '前一天',
                  onPressed: widget.onPrev,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  key: const Key('day-next'),
                  tooltip: '后一天',
                  onPressed: widget.onNext,
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  key: const Key('day-add-task'),
                  tooltip: '排任务',
                  onPressed: widget.onAddTask,
                  icon: const Icon(Icons.add_task),
                ),
                if (widget.aiLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    key: const Key('day-ai'),
                    tooltip: 'AI 排',
                    onPressed: widget.onAiSchedule,
                    icon: const Icon(Icons.auto_awesome, size: 20),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _scrollOffset.value = notification.metrics.pixels;
              return false;
            },
            child: DayGrid(
              day: widget.day,
              slices: widget.slices,
              isToday: widget.isToday,
              now: DateTime.now(),
              onEditSlice: widget.onEditSlice,
              suggested: widget.suggested,
              suggestedTasks: widget.suggestedTasks,
            ),
          ),
        ),
      ],
    );
  }
}
