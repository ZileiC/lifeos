import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/recurrence.dart';
import '../providers.dart';

enum TaskEditMode { once, weekly }

const List<String> _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

String _weekdayLabel(int day) => _weekdayLabels[day - 1];

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

class TaskEditorSheet extends ConsumerStatefulWidget {
  const TaskEditorSheet({super.key, this.existing, this.existingSlices = const []});

  final Record? existing;

  /// The task's day slices (used to prefill the plan fields and to update the
  /// single planned slice when the task is edited).
  final List<DaySlice> existingSlices;

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _estimate;
  late final TextEditingController _weeklyDuration;
  late int _urgency;
  late int _importance;
  late bool _pinned;
  late TaskEditMode _mode;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  DateTime? _startDate;
  TimeOfDay? _startTime;
  late Set<int> _weekdays;
  late TimeOfDay _weeklyStart;
  DateTime? _fromDate;
  DateTime? _toDate;
  DaySlice? _planSlice;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final recurrence = RecurrenceSpec.tryParse(existing?.recurrence);
    _mode = recurrence == null ? TaskEditMode.once : TaskEditMode.weekly;

    _title = TextEditingController(text: existing?.title ?? '');
    _note = TextEditingController(text: existing?.body ?? '');
    _estimate = TextEditingController(
      text: existing?.estimatedMinutes?.toString() ?? '',
    );
    _urgency = existing?.urgency ?? 5;
    _importance = existing?.importance ?? 5;
    _pinned = existing?.pinned ?? false;
    _dueDate = existing?.dueAt;
    _dueTime = existing != null && !existing.allDay
        ? TimeOfDay.fromDateTime(existing.dueAt!)
        : null;
    _startDate = existing?.startAt;
    _startTime = existing?.startAt != null
        ? TimeOfDay.fromDateTime(existing!.startAt!)
        : null;

    _weekdays = recurrence?.weekdays.toSet() ?? {_today().weekday};
    _weeklyStart = recurrence != null
        ? TimeOfDay(
            hour: recurrence.startMinutes ~/ 60,
            minute: recurrence.startMinutes % 60,
          )
        : const TimeOfDay(hour: 9, minute: 0);
    _weeklyDuration = TextEditingController(
      text: '${recurrence?.durationMinutes ?? existing?.estimatedMinutes ?? 60}',
    );
    _fromDate = recurrence?.fromDate ?? _today();
    _toDate = recurrence?.toDate ?? _today().add(const Duration(days: 30));

    final slices = [...widget.existingSlices]
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    if (recurrence == null && slices.isNotEmpty) {
      _planSlice = slices.first;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _estimate.dispose();
    _weeklyDuration.dispose();
    super.dispose();
  }

  /// Pickers must not leave the text fields focused: otherwise closing a
  /// picker pops the keyboard back up.
  Future<T?> _pick<T>(Future<T?> Function() open) async {
    FocusScope.of(context).unfocus();
    final result = await open();
    if (mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    return result;
  }

  Future<void> _pickDate() async {
    final picked = await _pick(() => showDatePicker(
          context: context,
          initialDate: _dueDate ?? _today(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        ));
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await _pick(() => showTimePicker(
          context: context,
          initialTime: _dueTime ?? const TimeOfDay(hour: 9, minute: 0),
        ));
    if (picked != null) {
      setState(() {
        _dueTime = picked;
        _dueDate ??= _today();
      });
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await _pick(() => showDatePicker(
          context: context,
          initialDate: _startDate ?? _today(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        ));
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _startTime ??= const TimeOfDay(hour: 9, minute: 0);
      });
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await _pick(() => showTimePicker(
          context: context,
          initialTime: _startTime ?? const TimeOfDay(hour: 9, minute: 0),
        ));
    if (picked != null) {
      setState(() {
        _startTime = picked;
        _startDate ??= _today();
      });
    }
  }

  Future<void> _pickWeeklyStart() async {
    final picked = await _pick(() => showTimePicker(
          context: context,
          initialTime: _weeklyStart,
        ));
    if (picked != null) {
      setState(() => _weeklyStart = picked);
    }
  }

  Future<void> _pickFrom() async {
    final picked = await _pick(() => showDatePicker(
          context: context,
          initialDate: _fromDate ?? _today(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        ));
    if (picked != null) {
      setState(() => _fromDate = picked);
    }
  }

  Future<void> _pickTo() async {
    final picked = await _pick(() => showDatePicker(
          context: context,
          initialDate: _toDate ?? _today(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        ));
    if (picked != null) {
      setState(() => _toDate = picked);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _showError('先写个标题');
      return;
    }
    final repo = ref.read(taskRepositoryProvider);
    try {
      if (_mode == TaskEditMode.weekly) {
        if (_weekdays.isEmpty) {
          _showError('选至少一天');
          return;
        }
        final duration = int.tryParse(_weeklyDuration.text.trim());
        if (duration == null || duration <= 0) {
          _showError('每次时长要填正整数分钟');
          return;
        }
        final from = _fromDate;
        final to = _toDate;
        if (from == null || to == null) {
          _showError('选起止日期');
          return;
        }
        if (to.isBefore(from)) {
          _showError('结束日期不能早于开始');
          return;
        }
        final spec = RecurrenceSpec(
          weekdays: _weekdays,
          startMinutes: _weeklyStart.hour * 60 + _weeklyStart.minute,
          durationMinutes: duration,
          fromDate: from,
          toDate: to,
        );
        if (!spec.isValid) {
          _showError('重复规则不合法');
          return;
        }
        if (_editing) {
          await repo.updateTask(
            widget.existing!.id,
            title: title,
            note: _note.text.trim(),
            urgency: _urgency,
            importance: _importance,
            pinned: _pinned,
            recurrence: spec,
          );
          await repo.replaceRecurringSlices(widget.existing!.id, spec);
        } else {
          await repo.createTask(
            title: title,
            note: _note.text.trim(),
            urgency: _urgency,
            importance: _importance,
            pinned: _pinned,
            recurrence: spec,
          );
        }
      } else {
        final estimate = int.tryParse(_estimate.text.trim());
        if (estimate == null || estimate <= 0) {
          _showError('预估总时长要填正整数分钟');
          return;
        }
        DateTime? dueAt;
        if (_dueDate != null) {
          dueAt = DateTime(
            _dueDate!.year,
            _dueDate!.month,
            _dueDate!.day,
            _dueTime?.hour ?? 0,
            _dueTime?.minute ?? 0,
          );
        }
        final dueHasTime = _dueTime != null;
        final existingRecurring = widget.existing != null &&
            RecurrenceSpec.tryParse(widget.existing!.recurrence) != null;

        // The DDL is the deadline, not the start. Either side can be missing:
        //   start + ddl -> [start, ddl]
        //   start only  -> [start, start + estimate]
        //   ddl only    -> [ddl - estimate, ddl]
        DateTime? startAt;
        if (_startDate != null) {
          startAt = DateTime(
            _startDate!.year,
            _startDate!.month,
            _startDate!.day,
            _startTime?.hour ?? 0,
            _startTime?.minute ?? 0,
          );
        }
        DateTime? planStart;
        DateTime? planEnd;
        if (startAt != null && dueAt != null) {
          planStart = startAt;
          planEnd = dueAt;
        } else if (startAt != null) {
          planStart = startAt;
          planEnd = startAt.add(Duration(minutes: estimate));
        } else if (dueAt != null && _dueTime != null) {
          planStart = dueAt.subtract(Duration(minutes: estimate));
          planEnd = dueAt;
        }

        String taskId;
        if (_editing) {
          taskId = widget.existing!.id;
          await repo.updateTask(
            taskId,
            title: title,
            note: _note.text.trim(),
            urgency: _urgency,
            importance: _importance,
            dueAt: dueAt,
            dueHasTime: dueHasTime,
            startAt: startAt,
            clearStart: startAt == null,
            estimatedMinutes: estimate,
            pinned: _pinned,
            clearRecurrence: existingRecurring,
          );
        } else {
          taskId = await repo.createTask(
            title: title,
            note: _note.text.trim(),
            urgency: _urgency,
            importance: _importance,
            dueAt: dueAt,
            dueHasTime: dueHasTime,
            startAt: startAt,
            estimatedMinutes: estimate,
            pinned: _pinned,
          );
        }

        if (planStart != null && planEnd != null) {
          final slice = _planSlice;
          if (slice != null) {
            await repo.updateSlice(slice.id, startAt: planStart, endAt: planEnd);
          } else {
            await repo.addSlice(
              taskId: taskId,
              startAt: planStart,
              endAt: planEnd,
            );
          }
        } else if (_planSlice != null) {
          await repo.deleteSlice(_planSlice!.id);
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      _showError('保存失败：$error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueLabel =
        _dueDate == null ? '未设置' : DateFormat('yyyy/MM/dd').format(_dueDate!);
    final fromLabel = _fromDate == null
        ? '未设置'
        : DateFormat('yyyy/MM/dd').format(_fromDate!);
    final toLabel =
        _toDate == null ? '未设置' : DateFormat('yyyy/MM/dd').format(_toDate!);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final height =
        (MediaQuery.sizeOf(context).height - viewInsets.bottom) * 0.9;

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _editing ? '编辑任务' : '新任务',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('task-title'),
                      controller: _title,
                      decoration: const InputDecoration(
                        labelText: '任务',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<TaskEditMode>(
                      segments: const [
                        ButtonSegment(
                          value: TaskEditMode.once,
                          label: Text('一次性'),
                        ),
                        ButtonSegment(
                          value: TaskEditMode.weekly,
                          label: Text('每周固定'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (values) {
                        setState(() => _mode = values.first);
                      },
                    ),
                    const SizedBox(height: 16),
                    _ScoreSelector(
                      label: 'Urgency（有多急）',
                      value: _urgency,
                      onChanged: (value) => setState(() => _urgency = value),
                      keyPrefix: 'urgency',
                    ),
                    const SizedBox(height: 12),
                    _ScoreSelector(
                      label: 'Importance（有多重要）',
                      value: _importance,
                      onChanged: (value) =>
                          setState(() => _importance = value),
                      keyPrefix: 'importance',
                    ),
                    const SizedBox(height: 16),
                    if (_mode == TaskEditMode.once) ...[
                      Text('开始（可选）', style: theme.textTheme.labelLarge),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        key: const Key('start-date'),
                        leading: const Icon(Icons.play_circle_outline),
                        title: const Text('开始日期'),
                        trailing: Text(
                          _startDate == null
                              ? '未设置'
                              : DateFormat('yyyy/MM/dd').format(_startDate!),
                        ),
                        onTap: _pickStartDate,
                      ),
                      if (_startDate != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          key: const Key('start-time'),
                          leading: const Icon(Icons.schedule),
                          title: const Text('开始时间'),
                          trailing: Text(
                            (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
                                .format(context),
                          ),
                          onTap: _pickStartTime,
                        ),
                      if (_startDate != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const Key('start-clear'),
                            onPressed: () => setState(() {
                              _startDate = null;
                              _startTime = null;
                            }),
                            child: const Text('清空开始'),
                          ),
                        ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined),
                        title: const Text('截止日期'),
                        trailing: Text(dueLabel),
                        onTap: _pickDate,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('含具体时刻'),
                        value: _dueTime != null,
                        onChanged: (value) {
                          if (value) {
                            _pickTime();
                          } else {
                            setState(() => _dueTime = null);
                          }
                        },
                        secondary: IconButton(
                          icon: const Icon(Icons.schedule),
                          onPressed: _pickTime,
                          tooltip: '选择时刻',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('task-estimate'),
                        controller: _estimate,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '预估总时长（分钟）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ] else ...[
                      Text('每周哪几天', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (var day = 1; day <= 7; day++)
                            FilterChip(
                              key: Key('weekday-$day'),
                              label: Text(_weekdayLabel(day)),
                              selected: _weekdays.contains(day),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _weekdays.add(day);
                                  } else {
                                    _weekdays.remove(day);
                                  }
                                });
                              },
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        key: const Key('weekly-start'),
                        leading: const Icon(Icons.schedule),
                        title: const Text('开始时间'),
                        trailing: Text(_weeklyStart.format(context)),
                        onTap: _pickWeeklyStart,
                      ),
                      TextField(
                        key: const Key('weekly-duration'),
                        controller: _weeklyDuration,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '每次时长（分钟）',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        key: const Key('weekly-from'),
                        leading: const Icon(Icons.event_outlined),
                        title: const Text('从'),
                        trailing: Text(fromLabel),
                        onTap: _pickFrom,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        key: const Key('weekly-to'),
                        leading: const Icon(Icons.event_available_outlined),
                        title: const Text('到'),
                        trailing: Text(toLabel),
                        onTap: _pickTo,
                      ),
                      Text(
                        '保存后自动生成区间内的日片；改规则不会自动重排已有日片。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('task-note'),
                      controller: _note,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '短备注（只在详情显示）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('置顶（任务列表排最前）'),
                      value: _pinned,
                      onChanged: (value) => setState(() => _pinned = value),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + viewInsets.bottom),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('task-save'),
                  onPressed: _save,
                  child: Text(_editing ? '保存' : '记下'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreSelector extends StatelessWidget {
  const _ScoreSelector({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.keyPrefix,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 1; i <= 10; i++)
              ChoiceChip(
                key: Key('$keyPrefix-$i'),
                label: Text('$i'),
                selected: value == i,
                onSelected: (_) => onChanged(i),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                labelStyle: theme.textTheme.labelSmall,
              ),
          ],
        ),
      ],
    );
  }
}
