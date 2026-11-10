import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/recurrence.dart';

import '../ai/ai_models.dart';
import '../ai/ai_schedule.dart';
import '../data/database.dart';
import '../data/task_repository.dart';
import '../providers.dart';
import 'ai_ask_sheet.dart';
import 'ai_settings_sheet.dart';
import 'ai_suggestion_sheet.dart';
import 'day_view.dart';
import 'slice_editor_sheet.dart';
import 'task_detail_sheet.dart';
import 'task_editor_sheet.dart';
import 'task_row.dart';
import 'theme.dart';

enum HomeSegment { tasks, day }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  HomeSegment _segment = HomeSegment.tasks;
  final Set<String> _selected = <String>{};
  final ScrollController _tasksScroll = ScrollController();
  final ValueNotifier<double> _tasksScrollOffset = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _tasksScroll.addListener(() {
      if (!_tasksScroll.hasClients) return;
      _tasksScrollOffset.value = _tasksScroll.offset;
    });
  }

  @override
  void dispose() {
    _tasksScroll.dispose();
    _tasksScrollOffset.dispose();
    super.dispose();
  }
  bool _selectionMode = false;
  AiSuggestion? _aiSuggestion;
  bool _aiLoading = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _aiSuggest(DateTime day) async {
    if (_aiLoading) return;
    final providerStore = ref.read(aiProviderStoreProvider);
    final providers = await providerStore.readProviders();
    final activeId = await providerStore.readActiveId();
    final provider = providers.firstWhere(
      (item) => item.id == activeId,
      orElse: () => providers.first,
    );
    final apiKey = await ref.read(aiKeyStoreProvider).read(provider.id);
    if (!mounted) return;
    if (apiKey == null || apiKey.isEmpty) {
      _toast('先在 AI 设置里填 API key');
      return;
    }

    setState(() => _aiLoading = true);
    try {
      final skill = await ref.read(schedulingSkillProvider.future);
      final service = AiScheduleService(
        ref.read(aiClientProvider),
        ref.read(taskRepositoryProvider),
        skill,
      );
      final suggestion = await service.suggest(
        provider: provider,
        apiKey: apiKey,
        targetDay: day,
      );
      if (!mounted) return;
      setState(() {
        _aiSuggestion = suggestion;
        _aiLoading = false;
      });

      final confirmed = await showModalBottomSheet<List<AiSliceSuggestion>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => AiSuggestionSheet(suggestion: suggestion),
      );
      if (!mounted) return;
      if (confirmed == null || confirmed.isEmpty) {
        setState(() => _aiSuggestion = null);
        return;
      }
      await service.apply(suggestion: suggestion, slices: confirmed);
      if (!mounted) return;
      setState(() => _aiSuggestion = null);
      _toast('已写入 ${confirmed.length} 块日片');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _aiLoading = false;
        _aiSuggestion = null;
      });
      _toast('AI 排程失败：$error');
    }
  }

  void _enterSelection(String id) {
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  Future<void> _openCreate() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const TaskEditorSheet(),
    );
  }

  Future<void> _openDetail(Record task) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TaskDetailSheet(task: task),
    );
  }

  Future<void> _openSlice(DaySliceWithTask entry) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SliceEditorSheet(
        task: entry.task,
        existing: entry.slice,
      ),
    );
  }

  Future<void> _openPlan(Record task, {DateTime? day}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SliceEditorSheet(task: task, initialDay: day),
    );
  }

  Future<void> _openTaskPicker(DateTime day) async {
    final tasks = ref.read(tasksProvider).value ?? const <Record>[];
    if (tasks.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先建一个任务')));
      return;
    }
    final picked = await showModalBottomSheet<Record>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final task in tasks)
              ListTile(
                title: Text(task.title),
                subtitle: Text(
                  'U${task.urgency ?? '—'}  I${task.importance ?? '—'}',
                ),
                onTap: () => Navigator.of(context).pop(task),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      await _openPlan(picked, day: day);
    }
  }

  Future<void> _deleteSelected() async {
    final ids = List<String>.of(_selected);
    if (ids.isEmpty) return;
    final repo = ref.read(taskRepositoryProvider);
    final token = await repo.deleteTasks(ids);
    _clearSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除 ${token.taskIds.length} 项'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await repo.restoreTasks(token);
          },
        ),
      ),
    );
  }

  Future<void> _moveSelected() async {
    final ids = List<String>.of(_selected);
    if (ids.isEmpty) return;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final repo = ref.read(taskRepositoryProvider);
    final snapshots = await repo.moveTasksToDay(ids, date);
    _clearSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已移到 ${DateFormat('M月d日').format(date)}'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            await repo.restoreDueDates(snapshots);
          },
        ),
      ),
    );
  }

  Widget _buildTasks(
    List<Record> tasks,
    Map<String, List<DaySlice>> byTask,
    List<DaySliceWithTask> daySlices,
    DateTime day,
  ) {
    final isToday = _sameDay(day, DateTime.now());
    final daySlicesIds = daySlices.map((entry) => entry.task.id).toSet();

    final dayTasks = tasks.where((task) {
      if (daySlicesIds.contains(task.id)) return true;
      final recurring = RecurrenceSpec.tryParse(task.recurrence);
      if (recurring != null) {
        final d = DateTime(day.year, day.month, day.day);
        final from = DateTime(
            recurring.fromDate.year, recurring.fromDate.month, recurring.fromDate.day);
        final to = DateTime(
            recurring.toDate.year, recurring.toDate.month, recurring.toDate.day);
        return recurring.weekdays.contains(d.weekday) &&
            !d.isBefore(from) &&
            !d.isAfter(to);
      }
      if (task.dueAt != null && _sameDay(task.dueAt!, day)) return true;
      if (task.startAt != null && _sameDay(task.startAt!, day)) return true;
      return false;
    }).toList();

    final dayTaskIds = dayTasks.map((task) => task.id).toSet();
    final backlog = tasks
        .where((task) =>
            !dayTaskIds.contains(task.id) &&
            RecurrenceSpec.tryParse(task.recurrence) == null &&
            task.dueAt == null &&
            task.startAt == null &&
            (byTask[task.id] ?? const <DaySlice>[]).isEmpty)
        .toList();

    final planned = daySlices.fold<int>(
        0, (sum, entry) => sum + entry.slice.endAt.difference(entry.slice.startAt).inMinutes);
    final load = (planned / 480).clamp(0.0, 1.0);

    Widget row(Record task, int index) => _Reveal(
          index: index,
          child: TaskRow(
            task: task,
            slices: byTask[task.id] ?? const <DaySlice>[],
            selectionMode: _selectionMode,
            selected: _selected.contains(task.id),
            onTap: () => _selectionMode
                ? _toggleSelection(task.id)
                : _openDetail(task),
            onLongPress: () => _enterSelection(task.id),
          ),
        );

    return CustomScrollView(
      controller: _tasksScroll,
      slivers: [
        SliverToBoxAdapter(
          child: _DayHead(
            day: day,
            isToday: isToday,
            onPrev: () => ref.read(selectedDayProvider.notifier).shift(-1),
            onNext: () => ref.read(selectedDayProvider.notifier).shift(1),
            onToday: () => ref.read(selectedDayProvider.notifier).today(),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Text(
                  '负荷',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppTheme.inkDim,
                        letterSpacing: 0.12,
                      ),
                ),
                const Spacer(),
                Text(
                  '${(planned / 60).toStringAsFixed(1)} / 8h',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.inkDim,
                      ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: load,
                minHeight: 3,
                backgroundColor: AppTheme.line,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _SectionLabel(label: '当天', count: dayTasks.length),
        ),
        if (dayTasks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Text(
                isToday ? '今天没有安排' : '这天没有安排',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.inkDim),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: dayTasks.length,
            itemBuilder: (context, index) => row(dayTasks[index], index),
          ),
        if (backlog.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionLabel(label: '待安排', count: backlog.length),
          ),
          SliverList.builder(
            itemCount: backlog.length,
            itemBuilder: (context, index) => row(backlog[index], index),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider).value ?? const <Record>[];
    final allSlices = ref.watch(allSlicesProvider).value ?? const <DaySlice>[];
    final day = ref.watch(selectedDayProvider);
    final daySlices =
        ref.watch(daySlicesProvider(day)).value ?? const <DaySliceWithTask>[];

    final byTask = <String, List<DaySlice>>{};
    for (final slice in allSlices) {
      (byTask[slice.taskId] ??= <DaySlice>[]).add(slice);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;

    return Scaffold(
      appBar: AppBar(
        title: AnimatedBuilder(
          animation: _tasksScrollOffset,
          builder: (context, child) {
            final t = MediaQuery.disableAnimationsOf(context)
                ? 0.0
                : (_tasksScrollOffset.value / 140).clamp(0.0, 1.0);
            return Transform.scale(
              scale: 1 - 0.08 * t,
              alignment: Alignment.centerLeft,
              child: Opacity(opacity: 1 - 0.25 * t, child: child),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('LifeOS'),
              const SizedBox(width: 7),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            key: const Key('ai-ask'),
            tooltip: '问 AI',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => AiAskSheet(targetDay: day),
            ),
          ),
          IconButton(
            key: const Key('ai-settings'),
            tooltip: 'AI 设置',
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => const AiSettingsSheet(),
            ),
          ),
          if (_selectionMode)
            TextButton(
              onPressed: _clearSelection,
              child: const Text('取消'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Row(
              children: [
                _SegmentTab(
                  label: '任务',
                  selected: _segment == HomeSegment.tasks,
                  onTap: () => setState(() => _segment = HomeSegment.tasks),
                ),
                const SizedBox(width: 22),
                _SegmentTab(
                  label: '日视图',
                  selected: _segment == HomeSegment.day,
                  onTap: () => setState(() => _segment = HomeSegment.day),
                ),
                const Spacer(),
                Text(
                  '${tasks.length} 项',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.inkDim,
                        letterSpacing: 0.04,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _segment == HomeSegment.tasks
                ? _buildTasks(tasks, byTask, daySlices, day)
                : DayView(
                    day: day,
                    slices: daySlices,
                    isToday: isToday,
                    onPrev: () =>
                        ref.read(selectedDayProvider.notifier).shift(-1),
                    onNext: () =>
                        ref.read(selectedDayProvider.notifier).shift(1),
                    onToday: () =>
                        ref.read(selectedDayProvider.notifier).today(),
                    onAddTask: () => _openTaskPicker(day),
                    onEditSlice: _openSlice,
                    onAiSchedule: () => _aiSuggest(day),
                    aiLoading: _aiLoading,
                    suggested: _aiSuggestion?.slices ??
                        const <AiSliceSuggestion>[],
                    suggestedTasks:
                        _aiSuggestion?.tasks ?? const <String, Record>{},
                  ),
          ),
        ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton(
              onPressed: _segment == HomeSegment.tasks
                  ? _openCreate
                  : () => _openTaskPicker(day),
              tooltip: _segment == HomeSegment.tasks ? '新任务' : '排任务',
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: _selectionMode
          ? BottomAppBar(
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('已选 ${_selected.length}'),
                  ),
                  const Spacer(),
                  TextButton(
                    key: const Key('batch-delete'),
                    onPressed: _deleteSelected,
                    child: const Text('删除'),
                  ),
                  TextButton(
                    key: const Key('batch-move'),
                    onPressed: _moveSelected,
                    child: const Text('移到某天'),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class _SegmentTab extends StatelessWidget {
  const _SegmentTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: selected ? AppTheme.ink : AppTheme.inkDim,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: AppTheme.durBase,
              curve: AppTheme.easeOut,
              width: selected ? 18 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reveal extends StatefulWidget {
  const _Reveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppTheme.durSlow,
    );
    final start = (widget.index % 8) * 0.06;
    final eased = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1, curve: AppTheme.easeOut),
    );
    _opacity = eased;
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.03),
      end: Offset.zero,
    ).animate(eased);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _DayHead extends StatelessWidget {
  const _DayHead({
    required this.day,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime day;
  final bool isToday;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: AppTheme.durBase,
                switchInCurve: AppTheme.easeOut,
                switchOutCurve: AppTheme.easeInOut,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.12),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  '${day.day}',
                  key: ValueKey('${day.year}-${day.month}-${day.day}'),
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontSize: 46,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.04,
                    height: 0.95,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${DateFormat('M月').format(day)} · 周${_weekdays[day.weekday - 1]}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppTheme.inkDim,
                  letterSpacing: 0.08,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (!isToday)
            TextButton(
              key: const Key('tasks-today'),
              onPressed: onToday,
              child: const Text('今天'),
            ),
          IconButton(
            key: const Key('tasks-prev'),
            tooltip: '前一天',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left, size: 24),
          ),
          IconButton(
            key: const Key('tasks-next'),
            tooltip: '后一天',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right, size: 24),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.lineSoft)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppTheme.inkDim,
              letterSpacing: 0.14,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(color: AppTheme.inkDim),
          ),
        ],
      ),
    );
  }
}