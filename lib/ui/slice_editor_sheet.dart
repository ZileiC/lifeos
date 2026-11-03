import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../providers.dart';

class SliceEditorSheet extends ConsumerStatefulWidget {
  const SliceEditorSheet({
    super.key,
    required this.task,
    this.existing,
    this.initialDay,
  });

  final Record task;
  final DaySlice? existing;
  final DateTime? initialDay;

  @override
  ConsumerState<SliceEditorSheet> createState() => _SliceEditorSheetState();
}

class _SliceEditorSheetState extends ConsumerState<SliceEditorSheet> {
  late DateTime _date;
  late TimeOfDay _time;
  late final TextEditingController _duration;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final now = DateTime.now();
    _date = existing?.startAt ??
        widget.initialDay ??
        DateTime(now.year, now.month, now.day);
    _time = existing != null
        ? TimeOfDay.fromDateTime(existing.startAt)
        : TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
    final minutes = existing != null
        ? existing.endAt.difference(existing.startAt).inMinutes
        : (widget.task.estimatedMinutes ?? 60);
    _duration = TextEditingController(text: '$minutes');
  }

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final duration = int.tryParse(_duration.text.trim());
    if (duration == null || duration <= 0) {
      _showError('时长要填正整数分钟');
      return;
    }
    final start = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final end = start.add(Duration(minutes: duration));
    final repo = ref.read(taskRepositoryProvider);
    try {
      if (widget.existing != null) {
        await repo.updateSlice(widget.existing!.id, startAt: start, endAt: end);
      } else {
        await repo.addSlice(
          taskId: widget.task.id,
          startAt: start,
          endAt: end,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      _showError('保存失败：$error');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这块日片？'),
        content: const Text('只删这块计划，不影响任务本身。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('slice-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(taskRepositoryProvider).deleteSlice(widget.existing!.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    ).add(Duration(minutes: int.tryParse(_duration.text.trim()) ?? 0));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null ? '排到某天' : '编辑日片',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(widget.task.title, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                key: const Key('slice-date'),
                leading: const Icon(Icons.event_outlined),
                title: const Text('日期'),
                trailing: Text(DateFormat('yyyy/MM/dd').format(_date)),
                onTap: _pickDate,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                key: const Key('slice-time'),
                leading: const Icon(Icons.schedule),
                title: const Text('开始时间'),
                trailing: Text(_time.format(context)),
                onTap: _pickTime,
              ),
              TextField(
                key: const Key('slice-duration'),
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '时长（分钟）',
                  helperText: '结束 ${DateFormat('HH:mm').format(end)}',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('slice-save'),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('slice-delete'),
                  onPressed: _delete,
                  child: const Text('删除这块日片'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
