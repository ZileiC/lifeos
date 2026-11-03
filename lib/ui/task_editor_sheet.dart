import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../providers.dart';

class TaskEditorSheet extends ConsumerStatefulWidget {
  const TaskEditorSheet({super.key, this.existing});

  final Record? existing;

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _estimate;
  late int _urgency;
  late int _importance;
  late bool _pinned;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
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
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _estimate.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dueTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _dueTime = picked;
        _dueDate ??= DateTime.now();
      });
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _showError('先写个标题');
      return;
    }
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
    final repo = ref.read(taskRepositoryProvider);

    try {
      if (_editing) {
        await repo.updateTask(
          widget.existing!.id,
          title: title,
          note: _note.text.trim(),
          urgency: _urgency,
          importance: _importance,
          dueAt: dueAt,
          dueHasTime: dueHasTime,
          estimatedMinutes: estimate,
          pinned: _pinned,
        );
      } else {
        await repo.createTask(
          title: title,
          note: _note.text.trim(),
          urgency: _urgency,
          importance: _importance,
          dueAt: dueAt,
          dueHasTime: dueHasTime,
          estimatedMinutes: estimate,
          pinned: _pinned,
        );
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
                onChanged: (value) => setState(() => _importance = value),
                keyPrefix: 'importance',
              ),
              const SizedBox(height: 16),
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
                title: const Text('置顶（长期任务）'),
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
