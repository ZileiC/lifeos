import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../ai/ai_models.dart';
import '../ai/ai_schedule.dart';
import '../data/database.dart';
import '../data/task_repository.dart';
import '../providers.dart';
import 'ai_settings_sheet.dart';
import 'ai_suggestion_sheet.dart';
import 'day_view.dart';
import 'slice_editor_sheet.dart';
import 'task_detail_sheet.dart';
import 'task_editor_sheet.dart';
import 'task_row.dart';

enum HomeSegment { tasks, day }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  HomeSegment _segment = HomeSegment.tasks;
  final Set<String> _selected = <String>{};
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
  ) {
    if (tasks.isEmpty) {
      return const Center(child: Text('记下第一件事'));
    }
    return ListView.separated(
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return TaskRow(
          task: task,
          slices: byTask[task.id] ?? const <DaySlice>[],
          selectionMode: _selectionMode,
          selected: _selected.contains(task.id),
          onTap: () =>
              _selectionMode ? _toggleSelection(task.id) : _openDetail(task),
          onLongPress: () => _enterSelection(task.id),
        );
      },
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
        title: const Text('LifeOS'),
        actions: [
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<HomeSegment>(
              segments: const [
                ButtonSegment(value: HomeSegment.tasks, label: Text('任务')),
                ButtonSegment(value: HomeSegment.day, label: Text('日视图')),
              ],
              selected: {_segment},
              onSelectionChanged: (values) {
                setState(() => _segment = values.first);
              },
            ),
          ),
          Expanded(
            child: _segment == HomeSegment.tasks
                ? _buildTasks(tasks, byTask)
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
