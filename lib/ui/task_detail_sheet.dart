import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/recurrence.dart';
import '../data/task_colors.dart';
import '../data/task_math.dart';
import '../providers.dart';
import 'slice_editor_sheet.dart';
import 'task_editor_sheet.dart';

String _weekdayShort(int day) =>
    const ['一', '二', '三', '四', '五', '六', '日'][day - 1];

class TaskDetailSheet extends ConsumerWidget {
  const TaskDetailSheet({super.key, required this.task});

  final Record task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = ref.watch(allSlicesProvider).value ?? const <DaySlice>[];
    final slices = all.where((slice) => slice.taskId == task.id).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final planned = TaskMath.plannedMinutes(slices);
    final remaining = TaskMath.remainingMinutes(task, slices);
    final recurrence = RecurrenceSpec.tryParse(task.recurrence);
    final color = Color(TaskColors.resolve(task.color, task.id));

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(task.title, style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(label: Text('U ${task.urgency ?? '—'}')),
                Chip(label: Text('I ${task.importance ?? '—'}')),
                if (task.pinned) const Chip(label: Text('置顶')),
              ],
            ),
            const SizedBox(height: 8),
            Text(_scheduleLabel(task, recurrence), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              _effortLabel(task, recurrence, planned, remaining),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (task.body.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('备注', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(task.body, key: const Key('detail-note')),
            ],
            const SizedBox(height: 16),
            Text('日片', style: theme.textTheme.labelLarge),
            if (slices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('还没有排片'),
              )
            else
              ...slices.map(
                (slice) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.view_timeline_outlined),
                  title: Text(
                    '${DateFormat('MM/dd HH:mm').format(slice.startAt)}'
                    ' – ${DateFormat('HH:mm').format(slice.endAt)}',
                  ),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => SliceEditorSheet(
                      task: task,
                      existing: slice,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.tonalIcon(
                  key: const Key('detail-plan'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => SliceEditorSheet(task: task),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('排一块'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: const Key('detail-edit'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => TaskEditorSheet(existing: task),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑'),
                ),
                const Spacer(),
                TextButton.icon(
                  key: const Key('detail-delete'),
                  onPressed: () => _delete(context, ref),
                  icon: Icon(Icons.delete_outline,
                      color: theme.colorScheme.error),
                  label: Text('删除',
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _scheduleLabel(Record task, RecurrenceSpec? recurrence) {
    if (recurrence != null) {
      final days = recurrence.weekdays.toList()..sort();
      final start = TimeOfDay(
        hour: recurrence.startMinutes ~/ 60,
        minute: recurrence.startMinutes % 60,
      );
      final offset = Duration(minutes: recurrence.durationMinutes);
      final endMinutes = recurrence.startMinutes + offset.inMinutes;
      final end = TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60);
      String fmt(TimeOfDay t) =>
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      return '每周${days.map(_weekdayShort).join('/')} · '
          '${fmt(start)}–${fmt(end)} · '
          '至 ${DateFormat('yyyy/MM/dd').format(recurrence.toDate)}';
    }
    final due = task.dueAt;
    if (due == null) return '无截止';
    return task.allDay
        ? '截止 ${DateFormat('yyyy/MM/dd').format(due)}'
        : '截止 ${DateFormat('yyyy/MM/dd HH:mm').format(due)}';
  }

  String _effortLabel(
    Record task,
    RecurrenceSpec? recurrence,
    int planned,
    int? remaining,
  ) {
    final estimate = task.estimatedMinutes;
    if (recurrence != null) {
      return '每次 ${estimate ?? '—'} 分钟 · 共 $planned 片';
    }
    return '预估 ${estimate ?? '—'} 分钟 · 已排 $planned 分钟'
        ' · 剩余 ${remaining ?? '—'} 分钟';
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除任务？'),
        content: const Text('任务和它的日片都会被隐藏（墓碑）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('detail-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(taskRepositoryProvider).deleteTasks([task.id]);
    if (context.mounted) Navigator.of(context).pop();
  }
}
