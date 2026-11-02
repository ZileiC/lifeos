import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/reminders.dart';
import '../data/repository.dart';
import '../data/rrule.dart';
import '../providers.dart';
import 'manage_lists_sheet.dart';

/// Sentinel returned by the repeat picker when the user explicitly taps
/// "no repeat". A null result still means "dismissed" (keep the current rule).
const Object _clearRrule = Object();

/// Bottom sheet for creating / editing a record.
/// existing == null means create mode.
Future<void> showEditRecordSheet(
  BuildContext context,
  WidgetRef ref, {
  RecordWithItems? existing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditRecordSheet(existing: existing),
  );
}

class _EditRecordSheet extends ConsumerStatefulWidget {
  const _EditRecordSheet({this.existing});

  final RecordWithItems? existing;

  @override
  ConsumerState<_EditRecordSheet> createState() => _EditRecordSheetState();
}

class _EditRecordSheetState extends ConsumerState<_EditRecordSheet> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _checkInput;
  String? _listId;
  // F2b: due = date + allDay flag + nullable time (time set iff !allDay).
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  bool _allDay = true;
  // F1c: span = result of two full "date -> time" picks (full DateTime pair,
  // cross-day capable; start-only allowed; clearable as a whole).
  DateTime? _startAt;
  DateTime? _endAt;
  // L2: selected reminder lead-time offsets (minutes before DDL).
  List<int> _reminders = const [];
  RRule? _rrule;
  bool _dirty = false;

  bool get _isEdit => widget.existing != null;

  Record get _r => widget.existing!.record;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: _isEdit ? _r.title : '');
    _body = TextEditingController(text: _isEdit ? _r.body : '');
    _checkInput = TextEditingController();
    _listId = _isEdit ? _r.listId : ref.read(selectedListProvider);
    // F2b: time is set only when !allDay; allDay leaves it unset.
    // NOTE: _r uses existing! — guard with _isEdit before touching it.
    // (New-create mode would throw null! — the v0.1.2 grey-screen incident,
    // full stack in WORKLOG 2026-09-07.)
    if (_isEdit) {
      final d = _r.dueAt;
      if (d != null) {
        _dueDate = DateTime(d.year, d.month, d.day);
        _allDay = _r.allDay;
        _dueTime = _allDay ? null : TimeOfDay(hour: d.hour, minute: d.minute);
      }
    }
    // F1c: echo spans as full timestamps (with date axis, cross-day capable).
    if (_isEdit) {
      final s = _r.startAt;
      final e = _r.endAt;
      _startAt = s;
      _endAt = e;
      _reminders = parseReminderOffsets(_r.reminderOffsets);
    }
    _rrule = _isEdit ? RRule.parse(_r.rrule) : null;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _checkInput.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final due = _composeDue();
    final (start, end) = _composeSpan();
    final reminders = _reminders;
    final repo = ref.read(repositoryProvider);
    if (_isEdit) {
      await repo.updateRecord(
        _r.id,
        title: title,
        body: _body.text.trim(),
        listId: _listId,
        clearList: _listId == null,
        dueAt: due,
        clearDue: due == null,
        allDay: _allDay,
        startAt: start,
        endAt: end,
        clearSpan: start == null && end == null,
        rrule: _rrule,
        clearRrule: _rrule == null,
        reminderOffsetsParam: reminders,
        clearReminders: false,
      );
    } else {
      // Creation: also collect checkitems typed but not yet submitted.
      final items = widget.existing?.items.map((e) => e.content).toList() ?? const [];
      await repo.createRecord(
        title: title,
        body: _body.text.trim(),
        listId: _listId,
        dueAt: due,
        allDay: _allDay,
        startAt: start,
        endAt: end,
        rrule: _rrule,
        reminderOffsets: reminders,
        checkitems: items,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  /// F2b: compose dueAt. allDay=true -> midnight of that day (no time shown);
  /// allDay=false -> day + explicit time (a picked 00:00 is a real 00:00).
  DateTime? _composeDue() {
    final d = _dueDate;
    if (d == null) return null;
    final day = DateTime(d.year, d.month, d.day);
    if (_allDay) return day;
    final t = _dueTime ?? const TimeOfDay(hour: 9, minute: 0);
    return day.add(Duration(hours: t.hour, minutes: t.minute));
  }

  /// F1c: compose the span. State is already full timestamps, no anchoring
  /// to dueDate/today; with both ends, swap by full timestamp (cross-day
  /// safe); single-sided spans pass through.
  (DateTime?, DateTime?) _composeSpan() {
    var s = _startAt;
    var e = _endAt;
    if (s == null && e == null) return (null, null);
    if (s != null && e != null && e.isBefore(s)) (s, e) = (e, s);
    return (s, e);
  }

  /// F2b: unified two-step pick = DatePicker -> (all-day | TimePicker).
  /// [initialDate]/[initialTime]/[initialAllDay] support echo; returns whether
  /// both steps confirmed.
  Future<bool> _pickDateTimeUnified({
    required ValueChanged<DateTime> onDate,
    required ValueChanged<(TimeOfDay?, bool)> onTimeResolved,
    DateTime? initialDate,
    TimeOfDay? initialTime,
    bool initialAllDay = true,
  }) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (pickedDate == null || !mounted) return false;
    onDate(pickedDate);

    // Time step: bottom sheet with an explicit all-day option.
    final resolved = await showModalBottomSheet<(TimeOfDay?, bool)>(
      context: context,
      builder: (ctx) => _TimeStepSheet(
        initialTime: initialTime,
        initialAllDay: initialAllDay,
      ),
    );
    if (resolved == null || !mounted) return false; // Time step cancelled: the date was already applied.
    onTimeResolved(resolved);
    return true;
  }

  /// F2b: due = unified two-step flow (date -> all-day/time).
  Future<void> _editDue() async {
    await _pickDateTimeUnified(
      initialDate: _dueDate,
      initialTime: _dueTime,
      initialAllDay: _allDay,
      onDate: (d) => setState(() => _dueDate = d),
      onTimeResolved: (r) => setState(() {
        final (t, allDay) = r;
        _dueTime = t;
        _allDay = allDay;
      }),
    );
  }

  /// F1c: span = two full "date -> time" picks.
  /// Start: DatePicker -> _TimeStepSheet; end follows the same flow with its
  /// date defaulting to the start date (editable -> cross-day). Start-only is
  /// allowed (cancel on either end step); "clear span" has its own entry.
  Future<void> _editSpan() async {
    final now = DateTime.now();

    // ---- start side ----
    final startDate = await showDatePicker(
      context: context,
      initialDate: _startAt ?? _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: '选择开始日期',
    );
    if (startDate == null || !mounted) return;

    final startResolved = await _pickSpanTimeStep(
      initialDate: startDate,
      initialTime: _startAt == null
          ? null
          : TimeOfDay(hour: _startAt!.hour, minute: _startAt!.minute),
    );
    if (startResolved == null || !mounted) return; // Cancelled = leave unchanged.
    final (startTime, startAllDay) = startResolved;

    // ---- end side (date defaults to start date; editable -> cross-day) ----
    final existingEndDay = _endAt == null
        ? null
        : DateTime(_endAt!.year, _endAt!.month, _endAt!.day);
    final endDate = await showDatePicker(
      context: context,
      initialDate: existingEndDay ??
          DateTime(startDate.year, startDate.month, startDate.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: '选择结束日期',
    );
    if (endDate == null || !mounted) {
      // End-side cancel = keep start only.
      setState(() {
        _startAt = DateTime(startDate.year, startDate.month, startDate.day)
            .add(Duration(
                hours: startTime?.hour ?? 0,
                minutes: startTime?.minute ?? 0));
        _endAt = null;
      });
      return;
    }

    final endResolved = await _pickSpanTimeStep(
      initialDate: endDate,
      initialTime: _endAt == null
          ? (startTime ?? const TimeOfDay(hour: 10, minute: 0))
          : TimeOfDay(hour: _endAt!.hour, minute: _endAt!.minute),
    );
    if (endResolved == null || !mounted) {
      // Time-step cancel = keep start only.
      setState(() {
        _startAt = DateTime(startDate.year, startDate.month, startDate.day)
            .add(Duration(
                hours: startTime?.hour ?? 0,
                minutes: startTime?.minute ?? 0));
        _endAt = null;
      });
      return;
    }
    final (endTime, endAllDay) = endResolved;

    setState(() {
      _startAt = DateTime(startDate.year, startDate.month, startDate.day)
          .add(Duration(
              hours: startTime?.hour ?? 0, minutes: startTime?.minute ?? 0));
      _endAt = DateTime(endDate.year, endDate.month, endDate.day).add(Duration(
          hours: endTime?.hour ?? 0, minutes: endTime?.minute ?? 0));
      // Swap by full timestamp when end < start (cross-day safe).
      if (_startAt != null && _endAt != null && _endAt!.isBefore(_startAt!)) {
        final t = _startAt;
        _startAt = _endAt;
        _endAt = t;
      }
    });
  }

  /// F1c: per-side time step = _TimeStepSheet (all-day | pick a time).
  /// Returns (TimeOfDay?, bool); null = user cancelled.
  /// All-day semantics: allDay=true stores a null time (midnight of the day;
  /// not shown as a time).
  Future<(TimeOfDay?, bool)?> _pickSpanTimeStep({
    required DateTime initialDate,
    TimeOfDay? initialTime,
  }) {
    return showModalBottomSheet<(TimeOfDay?, bool)>(
      context: context,
      builder: (ctx) => _TimeStepSheet(
        initialTime: initialTime,
        initialAllDay: initialTime == null,
      ),
    );
  }

  /// L2: reminder lead-time picker (multi-select bottom sheet).
  Future<void> _pickReminders() async {
    final picked = await showModalBottomSheet<List<int>>(
      context: context,
      builder: (ctx) => _ReminderPickerSheet(initial: _reminders),
    );
    if (picked != null && mounted) setState(() => _reminders = picked);
  }

  Future<void> _pickRrule() async {
    final choice = await showModalBottomSheet<Object?>(
      context: context,
      builder: (ctx) => SafeArea(
        // The preset list is long enough to exceed a phone-sized sheet; keep
        // it scrollable so the later rules (e.g. every N days) stay reachable.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child:
                    Text('重复', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              ListTile(
                leading: const Icon(Icons.block_rounded),
                title: const Text('不重复'),
                onTap: () => Navigator.pop(ctx, _clearRrule),
              ),
              for (final r in RRule.presets)
                ListTile(
                  leading: const Icon(Icons.repeat_rounded),
                  title: Text(r.label),
                  onTap: () => Navigator.pop(ctx, r),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return; // dismissed: keep the current rule
    setState(() {
      if (choice == _clearRrule) {
        _rrule = null;
      } else if (choice is RRule) {
        _rrule = choice;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lists = ref.watch(listsProvider).value ?? const [];
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title input.
            TextField(
              controller: _title,
              autofocus: !_isEdit,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: '标题',
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              maxLines: 1,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            // Body.
            TextField(
              controller: _body,
              style: const TextStyle(fontSize: 15, height: 1.5),
              decoration: const InputDecoration(
                hintText: '笔记内容（可留空）',
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              maxLines: null,
              minLines: 1,
            ),
            const SizedBox(height: 16),

            // Checkitems (existing ones show in edit mode only).
            if (_isEdit) ...[
              for (final item in widget.existing!.items)
                if (item.deletedAt == null)
                  Dismissible(
                    key: ValueKey(item.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      color: theme.colorScheme.error.withValues(alpha: 0.15),
                      child: Icon(Icons.delete_outline_rounded,
                          color: theme.colorScheme.error),
                    ),
                    onDismissed: (_) {
                      ref.read(repositoryProvider).removeCheckitem(item.id);
                      setState(() => _dirty = !_dirty);
                    },
                    child: CheckboxListTile(
                      value: item.done,
                      onChanged: (v) =>
                          ref.read(repositoryProvider).toggleCheckitem(item.id, v ?? false),
                      title: Text(item.content,
                          style: TextStyle(
                            fontSize: 14.5,
                            decoration:
                                item.done ? TextDecoration.lineThrough : null,
                          )),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _checkInput,
                      style: const TextStyle(fontSize: 14.5),
                      decoration: const InputDecoration(
                        hintText: '+ 添加勾选项',
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (text) {
                        if (text.trim().isEmpty) return;
                        ref
                            .read(repositoryProvider)
                            .addCheckitem(_r.id, text.trim());
                        _checkInput.clear();
                        setState(() => _dirty = !_dirty);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Property chips: list / due / span / repeat.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: Icon(Icons.folder_outlined,
                      size: 18,
                      color: _listId == null
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary),
                  label: Text(
                    _listId == null
                        ? '清单'
                        : lists.where((l) => l.id == _listId).map((l) => l.name).firstOrNull ?? '清单',
                  ),
                  onPressed: () async {
                    final picked = await _pickList(lists);
                    if (picked != '__cancel__') {
                      setState(() =>
                          _listId = picked == null ? null : picked as String);
                    }
                  },
                ),
                // F2b: due = unified two-step (date -> all-day/time).
                ActionChip(
                  avatar: Icon(Icons.event_outlined,
                      size: 18,
                      color: _dueDate == null
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary),
                  label: Text(_dueChipLabel),
                  onPressed: _editDue,
                ),
                // F1c: span = two full date->time picks; clearable once set.
                ActionChip(
                  avatar: Icon(Icons.timelapse_rounded,
                      size: 18,
                      color: _hasSpan
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant),
                  label: Text(_spanChipLabel),
                  onPressed: _hasSpan ? null : _editSpan,
                ),
                if (_hasSpan)
                  ActionChip(
                    avatar: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('清空时间段'),
                    onPressed: () => setState(() {
                      _startAt = null;
                      _endAt = null;
                    }),
                  ),
                if (_dueDate != null)
                  ActionChip(
                    avatar: Icon(Icons.repeat_rounded,
                        size: 18,
                        color: _rrule == null
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.secondary),
                    label: Text(_rrule?.label ?? '不重复'),
                    onPressed: _pickRrule,
                  ),
                // L2: reminder lead times (multi-select); needs a due date.
                if (_dueDate != null)
                  ActionChip(
                    avatar: Icon(Icons.notifications_active_outlined,
                        size: 18,
                        color: _reminders.isEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.primary),
                    label: Text(_reminderChipLabel),
                    onPressed: _pickReminders,
                  ),
                if (_dueDate != null)
                  ActionChip(
                    avatar: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('清除日期'),
                    onPressed: () => setState(() {
                      _dueDate = null;
                      _dueTime = null;
                      _allDay = true;
                      _rrule = null;
                      _reminders = const [];
                    }),
                  ),
              ],
            ),
            if (!_isEdit)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '提示：先选到期日才能设置循环',
                  style: TextStyle(
                      fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),

            const SizedBox(height: 20),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_isEdit ? '保存' : '添加',
                  style: const TextStyle(fontSize: 15.5)),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  final id = _r.id;
                  Navigator.pop(context);
                  await ref.read(repositoryProvider).deleteRecord(id);
                },
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: const Text('删除这条记录'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _hasSpan => _startAt != null || _endAt != null;

  /// F2b: due chip label (all-day / exact time).
  String get _dueChipLabel {
    final d = _dueDate;
    if (d == null) return '到期日';
    final date = DateFormat('M月d日').format(d);
    if (_allDay) return '$date 全天';
    final t = _dueTime ??
        (_r.dueAt != null
            ? TimeOfDay(hour: _r.dueAt!.hour, minute: _r.dueAt!.minute)
            : const TimeOfDay(hour: 9, minute: 0));
    return '$date ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// L2: reminder chip label, e.g. "15 min / 1 hour before" or none.
  String get _reminderChipLabel {
    if (_reminders.isEmpty) return '提前提醒';
    String one(int m) {
      if (m == 0) return '准时';
      if (m < 60) return '$m分钟';
      if (m == 60) return '1小时';
      if (m < 1440) return '${m ~/ 60}小时';
      return '1天';
    }
    return '提前 ${_reminders.map(one).join(' / ')}';
  }

  /// F1c: span chip label (date axis; cross-day shows both dates).
  String get _spanChipLabel {
    final s = _startAt;
    final e = _endAt;
    if (s == null && e == null) return '时间段';
    String f(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final dayFmt = DateFormat('M月d日');
    final sameDay =
        s != null && e != null && _dayOf(s) == _dayOf(e);
    if (s != null && e != null) {
      if (sameDay) return '${dayFmt.format(s)} ${f(s)}–${f(e)}';
      return '${dayFmt.format(s)} ${f(s)} – ${dayFmt.format(e)} ${f(e)}';
    }
    if (s != null) return '从 ${dayFmt.format(s)} ${f(s)}';
    return '到 ${dayFmt.format(e!)} ${f(e)}';
  }

  static DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

  Future<Object?> _pickList(List<ListRecord> lists) async {
    final result = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择清单', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('无（收件箱）'),
              onTap: () => Navigator.pop(ctx, null),
            ),
            for (final l in lists)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(l.name),
                onTap: () => Navigator.pop(ctx, l.id),
              ),
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('新建清单…'),
              onTap: () => Navigator.pop(ctx, '__new__'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result == '__new__') {
      if (!mounted) return '__cancel__';
      await showManageListsSheet(context);
      return '__cancel__';
    }
    return result ?? '__cancel__';
  }
}

/// F2b: time-step bottom sheet — an explicit all-day option plus
/// the standard TimePicker. Returns (TimeOfDay?, bool): all-day =
/// (null, true); specific time = (t, false).
class _TimeStepSheet extends StatefulWidget {
  const _TimeStepSheet({this.initialTime, this.initialAllDay = true});

  final TimeOfDay? initialTime;
  final bool initialAllDay;

  @override
  State<_TimeStepSheet> createState() => _TimeStepSheetState();
}

class _TimeStepSheetState extends State<_TimeStepSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDay = widget.initialAllDay && widget.initialTime == null;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('选择时刻', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: Icon(Icons.event_available_rounded,
                color: allDay ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
            title: const Text('全天任务'),
            subtitle: const Text('不指定具体时刻'),
            trailing: allDay
                ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                : null,
            onTap: () => Navigator.pop(context, (null, true)),
          ),
          ListTile(
            leading: const Icon(Icons.schedule_rounded),
            title: const Text('指定时刻'),
            subtitle: widget.initialTime != null
                ? Text('${widget.initialTime!.hour.toString().padLeft(2, '0')}:'
                    '${widget.initialTime!.minute.toString().padLeft(2, '0')}')
                : null,
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: widget.initialTime ?? const TimeOfDay(hour: 9, minute: 0),
              );
              if (t != null && context.mounted) {
                Navigator.pop(context, (t, false));
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// L2: multi-select reminder lead-time picker.
/// Multi-select rationale: pairing a heads-up ("1 day / 1 hour before") with
/// a last-call ("15 minutes / on time") is the common pattern; single-select
/// would force a lossy choice.
class _ReminderPickerSheet extends StatefulWidget {
  const _ReminderPickerSheet({required this.initial});

  final List<int> initial;

  @override
  State<_ReminderPickerSheet> createState() => _ReminderPickerSheetState();
}

class _ReminderPickerSheetState extends State<_ReminderPickerSheet> {
  late final Set<int> _selected = widget.initial.toSet();

  String _label(int m) {
    if (m == 0) return '准时';
    if (m < 60) return '$m分钟';
    if (m == 60) return '1小时';
    if (m < 1440) return '${m ~/ 60}小时';
    return '1天';
  }

  String _sub(int m) {
    if (m == 0) return '到期那一刻提醒';
    if (m < 60) return '到期前 $m 分钟';
    if (m == 1440) return '到期前 1 天';
    return '到期前 ${m ~/ 60} 小时';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('提前提醒（可多选）',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final m in kReminderOffsetPresets)
                  CheckboxListTile(
                    value: _selected.contains(m),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(m);
                      } else {
                        _selected.remove(m);
                      }
                    }),
                    title: Text(_label(m)),
                    subtitle: Text(_sub(m)),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selected.isEmpty ? '不设置提醒' : '已选 ${_selected.length} 项',
                    style: TextStyle(
                        fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _selected.toList()),
                  child: const Text('确定'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
