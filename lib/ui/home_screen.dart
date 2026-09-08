import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/repository.dart';
import '../data/rrule.dart';
import '../providers.dart';
import '../services/notification_service.dart';
import 'edit_record_sheet.dart';
import 'manage_lists_sheet.dart';

final _dateFmt = DateFormat('M月d日');

/// L2: in-app banner when notification permission is missing. Shows once per
/// app run (per dismissed state), offers a jump to system settings.
class _PermissionBanner extends StatefulWidget {
  const _PermissionBanner();

  @override
  State<_PermissionBanner> createState() => _PermissionBannerState();
}

class _PermissionBannerState extends State<_PermissionBanner> {
  bool? _granted; // null = not yet checked
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.canScheduleExact.then((ok) {
      if (mounted) setState(() => _granted = ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_granted != false || _dismissed) return const SizedBox.shrink();
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.notifications_off_outlined,
                  size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('通知权限未开启，到期提醒无法送达',
                    style: TextStyle(fontSize: 13)),
              ),
              TextButton(
                onPressed: () async {
                  await NotificationService.instance.requestPermission();
                  final ok =
                      await NotificationService.instance.canScheduleExact;
                  if (mounted) setState(() => _granted = ok);
                },
                child: const Text('去开启'),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _dismissed = true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(viewKindProvider);
    final lists = ref.watch(listsProvider).value ?? const [];
    final selectedList = ref.watch(selectedListProvider);
    final listName = selectedList == null
        ? null
        : lists.where((l) => l.id == selectedList).map((l) => l.name).firstOrNull;

    final titles = switch (kind) {
      ViewKind.inbox => listName ?? '收件箱',
      ViewKind.today => '今日',
      ViewKind.done => '已完成',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(titles),
        actions: [
          if (kind != ViewKind.done)
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: '已完成',
              onPressed: () =>
                  ref.read(viewKindProvider.notifier).set(ViewKind.done),
            ),
          if (kind == ViewKind.done)
            IconButton(
              icon: const Icon(Icons.task_alt_rounded),
              tooltip: '收件箱',
              onPressed: () =>
                  ref.read(viewKindProvider.notifier).set(ViewKind.inbox),
            ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          // L2: notification permission banner (degraded path).
          const _PermissionBanner(),
          Expanded(child: RecordList(kind: kind)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showEditRecordSheet(context, ref),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }
}

class RecordList extends ConsumerStatefulWidget {
  const RecordList({super.key, required this.kind});

  final ViewKind kind;

  @override
  ConsumerState<RecordList> createState() => _RecordListState();
}

class _RecordListState extends ConsumerState<RecordList> {
  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  void _exitSelection() => setState(_selected.clear);

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final records = ref.watch(recordsProvider);

    return records.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (items) {
        if (items.isEmpty) return _EmptyState(kind: kind);
        return RefreshIndicator(
          onRefresh: () async {
            _exitSelection();
            ref.invalidate(recordsProvider);
          },
          child: Stack(
            children: [
              ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 4, 16, _selecting ? 120 : 96),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final data = items[i];
                  final id = data.record.id;
                  return RecordCard(
                    data: data,
                    selecting: _selecting,
                    selected: _selected.contains(id),
                    onSelectToggle: () => _toggleSelect(id),
                    onLongPress: () {
                      if (!_selecting) _toggleSelect(id);
                    },
                  );
                },
              ),
              // F4: multi-select bottom action bar.
              if (_selecting)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _BulkActionBar(
                    kind: kind,
                    selectedIds: _selected.toList(),
                    onDone: _exitSelection,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// F4 bulk action bar. Complete/undo per view context; delete is tombstoned.
class _BulkActionBar extends ConsumerWidget {
  const _BulkActionBar({
    required this.kind,
    required this.selectedIds,
    required this.onDone,
  });

  final ViewKind kind;
  final List<String> selectedIds;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(repositoryProvider);
    final n = selectedIds.length;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '已选 $n 项',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('退出'),
                onPressed: onDone,
              ),
              const SizedBox(width: 4),
              // View context: done view offers undo, others offer complete.
              if (kind == ViewKind.done)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('取消完成'),
                  onPressed: () async {
                    await repo.setCompletedBulk(selectedIds, false);
                    onDone();
                  },
                )
              else
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('完成'),
                  onPressed: () async {
                    await repo.setCompletedBulk(selectedIds, true);
                    onDone();
                  },
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('删除'),
                onPressed: () => _confirmDelete(context, repo),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, RecordRepository repo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 ${selectedIds.length} 条记录？'),
        content: const Text('记录将进入回收（可同步标记），不在任何视图显示。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repo.deleteRecordsBulk(selectedIds);
      onDone();
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.kind});

  final ViewKind kind;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (kind) {
      ViewKind.inbox => (Icons.inbox_outlined, '收件箱是空的\n点右下角 + 记点什么'),
      ViewKind.today => (Icons.wb_sunny_outlined, '今天没有安排\n给记录设个到期日就会出现在这里'),
      ViewKind.done => (Icons.history_rounded, '近 30 天没有完成记录'),
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class RecordCard extends ConsumerWidget {
  const RecordCard({
    super.key,
    required this.data,
    this.selecting = false,
    this.selected = false,
    this.onSelectToggle,
    this.onLongPress,
  });

  final RecordWithItems data;
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelectToggle;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.read(repositoryProvider);
    final r = data.record;
    final done = r.completedAt != null;

    final hasContent = r.body.trim().isNotEmpty || data.items.isNotEmpty;

    // Selection border.
    final borderColor =
        selected ? theme.colorScheme.primary : theme.colorScheme.outline;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // F3b: card body = detail entry; in multi-select a tap = select.
        onTap: selecting
            ? onSelectToggle
            : () => showEditRecordSheet(context, ref, existing: data),
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: borderColor, width: selected ? 1.6 : 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Done dot: tappable in every view; toggles completion only,
              // never opens the detail sheet. Gesture isolation: the dot's
              // InkWell consumes the tap so it does not reach the card's.
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _DoneButton(
                  done: done,
                  onChanged: selecting
                      ? null
                      : (v) => repo.setCompleted(r.id, v),
                ),
              ),
              const SizedBox(width: 6),
              // Content area.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (r.pinned) ...[
                            Icon(Icons.push_pin_rounded,
                                size: 14, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              r.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                                decoration:
                                    done ? TextDecoration.lineThrough : null,
                                color: done
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (r.body.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          r.body.trim(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      // Checkitem preview (max 2).
                      if (data.items.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ...data.items.take(2).map((item) => Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    item.done
                                        ? Icons.check_box_outlined
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 16,
                                    color: item.done
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item.content,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: item.done
                                            ? theme.colorScheme.onSurfaceVariant
                                            : theme.colorScheme.onSurface
                                                .withValues(alpha: 0.85),
                                        decoration: item.done
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        if (data.items.length > 2)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '还有 ${data.items.length - 2} 项…',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                      // Meta row: due / time span / recurrence.
                      if (r.dueAt != null || r.rrule != null || r.startAt != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (r.dueAt != null) ...[
                              Icon(Icons.event_outlined,
                                  size: 14,
                                  color: _dueColor(context, r.dueAt!, done)),
                              const SizedBox(width: 4),
                              Text(
                                _dueLabel(r.dueAt!, r.allDay),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: _dueColor(context, r.dueAt!, done),
                                ),
                              ),
                            ],
                            // F1/F1c: time span display.
                            if (r.startAt != null) ...[
                              const SizedBox(width: 10),
                              Icon(Icons.timelapse_rounded,
                                  size: 14, color: theme.colorScheme.secondary),
                              const SizedBox(width: 4),
                              Text(
                                _spanLabel(r.startAt!, r.endAt),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                            ],
                            if (r.rrule != null) ...[
                              const SizedBox(width: 10),
                              Icon(Icons.repeat_rounded,
                                  size: 14, color: theme.colorScheme.secondary),
                              const SizedBox(width: 4),
                              Text(
                                RRule.parse(r.rrule)?.label ?? '',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: theme.colorScheme.secondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Pin button (hidden in multi-select mode).
              if (!selecting && !done)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    r.pinned
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    size: 18,
                    color: r.pinned
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () =>
                      repo.updateRecord(r.id, pinned: !r.pinned),
                ),
              if (hasContent) const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }

  // Color is decided at day granularity — anything due today (even later
  // today) is not overdue; time-of-day only affects the label (regression
  // guard).
  Color _dueColor(BuildContext context, DateTime due, bool done) {
    final theme = Theme.of(context);
    if (done) return theme.colorScheme.onSurfaceVariant;
    final today = DateTime.now();
    final d0 = DateTime(today.year, today.month, today.day);
    final due0 = DateTime(due.year, due.month, due.day);
    if (due0.isBefore(d0)) return theme.colorScheme.error; // overdue
    if (due0.isAtSameMomentAs(d0)) return theme.colorScheme.primary; // today
    return theme.colorScheme.onSurfaceVariant;
  }

  // F2b: show time only when !allDay; all-day shows the date alone.
  String _dueLabel(DateTime due, bool allDay) {
    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    final due0 = DateTime(due.year, due.month, due.day);
    final diff = due0.difference(d0).inDays;
    final timePart = allDay
        ? ''
        : ' ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return '今天$timePart';
    if (diff == 1) return '明天$timePart';
    if (diff == -1) return '昨天$timePart';
    if (diff < 0) return '逾期 ${_dateFmt.format(due)}$timePart';
    return '${_dateFmt.format(due)}$timePart';
  }

  // F1c span label (date axis included; cross-day shows both dates).
  String _spanLabel(DateTime start, DateTime? end) {
    String f(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final dayFmt = DateFormat('M月d日');
    if (end == null) return '从 ${dayFmt.format(start)} ${f(start)}';
    final sameDay = DateTime(start.year, start.month, start.day) ==
        DateTime(end.year, end.month, end.day);
    if (sameDay) return '${dayFmt.format(start)} ${f(start)}–${f(end)}';
    return '${dayFmt.format(start)} ${f(start)} – ${dayFmt.format(end)} ${f(end)}';
  }
}

/// Done button: ring -> filled check.
/// F3b: tappable in every view; onChanged is null only in multi-select.
class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.done, required this.onChanged});

  final bool done;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onChanged == null ? null : () => onChanged!(!done),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? theme.colorScheme.primary : Colors.transparent,
            border: Border.all(
              color: done ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              width: 1.8,
            ),
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 15, color: Color(0xFF10202B))
              : null,
        ),
      ),
    );
  }
}

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(listsProvider).value ?? const [];
    final selected = ref.watch(selectedListProvider);
    final kind = ref.watch(viewKindProvider);

    Widget tile({
      required IconData icon,
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: ListTile(
              leading: Icon(icon, size: 22,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant),
              title: Text(label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
              dense: true,
            ),
          ),
        ),
      );
    }

    return Drawer(
      width: 280,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'LifeOS',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5),
              ),
            ),
            const SizedBox(height: 4),
            tile(
              icon: Icons.inbox_outlined,
              label: '收件箱',
              selected: kind == ViewKind.inbox && selected == null,
              onTap: () => _go(ref, context, ViewKind.inbox, null),
            ),
            tile(
              icon: Icons.wb_sunny_outlined,
              label: '今日',
              selected: kind == ViewKind.today,
              onTap: () => _go(ref, context, ViewKind.today, null),
            ),
            const Divider(height: 24, indent: 20, endIndent: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text('清单',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 1)),
            ),
            Expanded(
              child: lists.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('还没有清单',
                          style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    )
                  : ListView(
                      children: [
                        for (final l in lists)
                          tile(
                            icon: Icons.folder_outlined,
                            label: l.name,
                            selected: kind == ViewKind.inbox && selected == l.id,
                            onTap: () => _go(ref, context, ViewKind.inbox, l.id),
                          ),
                      ],
                    ),
            ),
            const Divider(height: 8),
            tile(
              icon: Icons.check_circle_outline_rounded,
              label: '已完成',
              selected: kind == ViewKind.done,
              onTap: () => _go(ref, context, ViewKind.done, null),
            ),
            tile(
              icon: Icons.tune_rounded,
              label: '管理清单',
              selected: false,
              onTap: () {
                Navigator.pop(context);
                showManageListsSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _go(WidgetRef ref, BuildContext context, ViewKind kind, String? listId) {
    ref.read(viewKindProvider.notifier).set(kind);
    ref.read(selectedListProvider.notifier).set(listId);
    Navigator.pop(context);
  }
}
