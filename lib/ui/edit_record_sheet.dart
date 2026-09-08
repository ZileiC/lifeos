import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../data/repository.dart';
import '../data/rrule.dart';
import '../providers.dart';
import 'manage_lists_sheet.dart';

/// 新建 / 编辑记录的底部弹层。
/// existing == null 时是新建模式。
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
  // F2b：到期 = 日期 + allDay 标记 + 可空时刻（allDay=false 时时刻必有值）
  DateTime? _dueDate;
  TimeOfDay? _dueTime;
  bool _allDay = true;
  // F1c：区间 = 两次完整「日期→时刻」选择的结果（完整 DateTime 对，
  // 可跨天；可只设开始；可整体清空）
  DateTime? _startAt;
  DateTime? _endAt;
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
    // F2b：allDay=false 才有时刻；allDay=true 时刻视为未设。
    // 注意 _r 用了 existing!，必须先判 _isEdit 再碰（新建模式下 _r 会 null 崩，
    // v0.1.2 灰屏事故根因——取证堆栈见 WORKLOG 2026-09-07）。
    if (_isEdit) {
      final d = _r.dueAt;
      if (d != null) {
        _dueDate = DateTime(d.year, d.month, d.day);
        _allDay = _r.allDay;
        _dueTime = _allDay ? null : TimeOfDay(hour: d.hour, minute: d.minute);
      }
    }
    // F1c：区间回显完整时间戳（含日期轴，支持跨天）
    if (_isEdit) {
      final s = _r.startAt;
      final e = _r.endAt;
      _startAt = s;
      _endAt = e;
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
      );
    } else {
      // 新建：把输入框里没按回车的残留勾选项也收进来
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
        checkitems: items,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  /// F2b：合成 dueAt。allDay=true → 当天零点（展示不显时刻）；
  /// allDay=false → 当天 + 显式时刻（用户显式选 00:00 就是真实 00:00）。
  DateTime? _composeDue() {
    final d = _dueDate;
    if (d == null) return null;
    final day = DateTime(d.year, d.month, d.day);
    if (_allDay) return day;
    final t = _dueTime ?? const TimeOfDay(hour: 9, minute: 0);
    return day.add(Duration(hours: t.hour, minutes: t.minute));
  }

  /// F1c：合成区间。状态即完整时间戳，无需锚定 dueDate/今天；
  /// 双边齐时按完整时间戳对调（跨天安全），单边原样保留。
  (DateTime?, DateTime?) _composeSpan() {
    var s = _startAt;
    var e = _endAt;
    if (s == null && e == null) return (null, null);
    if (s != null && e != null && e.isBefore(s)) (s, e) = (e, s);
    return (s, e);
  }

  /// F2b：统一两步时间选择 = DatePicker → (全天任务 | TimePicker)。
  /// [initialDate] [initialTime] [initialAllDay] 支持回显；返回是否确认。
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

    // 时刻步骤：底部弹层，显式提供「全天任务」选项
    final resolved = await showModalBottomSheet<(TimeOfDay?, bool)>(
      context: context,
      builder: (ctx) => _TimeStepSheet(
        initialTime: initialTime,
        initialAllDay: initialAllDay,
      ),
    );
    if (resolved == null || !mounted) return false; // 取消时刻步骤：日期已更新
    onTimeResolved(resolved);
    return true;
  }

  /// F2b：到期时间 = 统一两步流程（日期 → 全天/时刻）
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

  /// F1c：区间 = 两次完整的「日期→时刻」选择。
  /// 开始：DatePicker → _TimeStepSheet；结束同流程，日期默认 = 开始日期（可改，
  /// 支持跨天）。可只设开始（结束侧任意一步取消）；「清空时间段」另有入口。
  Future<void> _editSpan() async {
    final now = DateTime.now();

    // —— 开始侧 ——
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
    if (startResolved == null || !mounted) return; // 取消 = 不改动
    final (startTime, startAllDay) = startResolved;

    // —— 结束侧（日期默认 = 开始日期，可改 → 跨天）——
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
      // 结束侧取消 = 只保留开始
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
      // 时刻步骤取消 = 只保留开始
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
      // 结束早于开始按完整时间戳对调（跨天安全）
      if (_startAt != null && _endAt != null && _endAt!.isBefore(_startAt!)) {
        final t = _startAt;
        _startAt = _endAt;
        _endAt = t;
      }
    });
  }

  /// F1c：区间侧的时刻步骤 = _TimeStepSheet（全天任务 | 指定时刻）。
  /// 返回 (TimeOfDay?, bool)；null = 用户取消。
  /// 区间的全天语义：allDay=true → 时刻记 null（存当天零点，展示不显时刻）。
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

  Future<void> _pickRrule() async {
    final choice = await showModalBottomSheet<RRule?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('重复', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded),
              title: const Text('不重复'),
              onTap: () => Navigator.pop(ctx, null),
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
    );
    if (choice != null || mounted) {
      // choice == null 且用户点了"不重复"也进来；取消弹层（点外部）不改变
      if (choice != null || _rrule != null) setState(() => _rrule = choice);
    }
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
            // 标题输入
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
            // 正文
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

            // 勾选项（仅编辑模式展示已有项）
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

            // 属性行：清单 / 到期 / 时间段 / 循环
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
                // F2b：到期 = 统一两步（日期 → 全天/时刻）
                ActionChip(
                  avatar: Icon(Icons.event_outlined,
                      size: 18,
                      color: _dueDate == null
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.primary),
                  label: Text(_dueChipLabel),
                  onPressed: _editDue,
                ),
                // F1b：时间段 = 两步 TimePicker；已设可清空
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
                if (_dueDate != null)
                  ActionChip(
                    avatar: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('清除日期'),
                    onPressed: () => setState(() {
                      _dueDate = null;
                      _dueTime = null;
                      _allDay = true;
                      _rrule = null;
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

  /// F2b：到期 chip 文案（全天 / 具体时刻）
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

  /// F1c：时间段 chip 文案（带日期轴；跨天显示两端日期）
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

/// F2b：时刻选择步骤的底部弹层——「全天任务」显式选项 + 标准 TimePicker。
/// 返回 (TimeOfDay?, bool)：全天 = (null, true)；具体时刻 = (t, false)。
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
