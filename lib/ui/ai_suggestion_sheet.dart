import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../ai/ai_models.dart';

/// Bottom sheet that previews an AI suggestion: the summary, the suggested
/// slices (checkbox + time + reason), the validator issues and the AI's
/// conflicts. Returns the selected (possibly edited) slices on confirm, or null
/// on ignore. It never writes anything itself.
class AiSuggestionSheet extends StatefulWidget {
  const AiSuggestionSheet({super.key, required this.suggestion});

  final AiSuggestion suggestion;

  @override
  State<AiSuggestionSheet> createState() => _AiSuggestionSheetState();
}

class _AiSuggestionSheetState extends State<AiSuggestionSheet> {
  late final List<AiSliceSuggestion> _slices;
  late final Set<int> _selected;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _slices = List<AiSliceSuggestion>.of(widget.suggestion.slices);
    _selected = Set<int>.from(
      List<int>.generate(_slices.length, (index) => index),
    );
  }

  Future<void> _editTime(int index) async {
    final slice = _slices[index];
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(slice.startAt),
      helpText: '建议开始时间',
    );
    if (start == null) return;
    final newStart = DateTime(
      slice.startAt.year,
      slice.startAt.month,
      slice.startAt.day,
      start.hour,
      start.minute,
    );
    final newEnd = newStart.add(slice.endAt.difference(slice.startAt));
    setState(() {
      _slices[index] = AiSliceSuggestion(
        taskId: slice.taskId,
        startAt: newStart,
        endAt: newEnd,
        reason: slice.reason,
      );
    });
  }

  void _confirm() {
    final chosen = _selected.toList()..sort();
    Navigator.of(context).pop(
      chosen.map((index) => _slices[index]).toList(),
    );
  }

  void _ignore() => Navigator.of(context).pop(null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = widget.suggestion;
    final taskColor = <String, Color>{
      for (final entry in suggestion.tasks.entries)
        entry.key: _taskColor(entry.value),
    };
    final errors = suggestion.issues.where((issue) => issue.isError).toList();
    final warnings =
        suggestion.issues.where((issue) => !issue.isError).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text('AI 建议', style: theme.textTheme.titleLarge),
            ),
            if (suggestion.answer.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  suggestion.answer,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (suggestion.conflicts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _IssueBox(
                  color: theme.colorScheme.error,
                  lines: suggestion.conflicts,
                ),
              ),
            if (errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _IssueBox(
                  color: theme.colorScheme.error,
                  lines: errors.map((issue) => issue.message).toList(),
                ),
              ),
            if (warnings.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _IssueBox(
                  color: const Color(0xFFD9B36C),
                  lines: warnings.map((issue) => issue.message).toList(),
                ),
              ),
            if (_slices.isEmpty)
              const Expanded(
                child: Center(child: Text('AI 没有给出可用的建议块')),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _slices.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final slice = _slices[index];
                    final task = suggestion.tasks[slice.taskId];
                    final color = taskColor[slice.taskId] ?? theme.colorScheme.primary;
                    final start = DateFormat('HH:mm').format(slice.startAt);
                    final end = DateFormat('HH:mm').format(slice.endAt);
                    return ListTile(
                      key: Key('suggestion-$index'),
                      leading: Checkbox(
                        key: Key('suggestion-check-$index'),
                        value: _selected.contains(index),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selected.add(index);
                            } else {
                              _selected.remove(index);
                            }
                          });
                        },
                      ),
                      title: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 16,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              task?.title ?? slice.taskId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        task == null
                            ? '$start–$end'
                            : '$start–$end · ${slice.reason}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        key: Key('suggestion-edit-$index'),
                        tooltip: '改时间',
                        icon: const Icon(Icons.schedule, size: 20),
                        onPressed: _editing
                            ? null
                            : () {
                                setState(() => _editing = true);
                                _editTime(index).whenComplete(() {
                                  if (mounted) setState(() => _editing = false);
                                });
                              },
                      ),
                    );
                  },
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('suggestion-ignore'),
                      onPressed: _ignore,
                      child: const Text('忽略'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('suggestion-confirm'),
                      onPressed: _selected.isEmpty ? null : _confirm,
                      child: Text('确认写入（${_selected.length}）'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _taskColor(dynamic task) => Color(
        task.color is int
            ? task.color as int
            : 0xFF8FB4CC,
      );
}

class _IssueBox extends StatelessWidget {
  const _IssueBox({required this.color, required this.lines});

  final Color color;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '• $line',
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
        ],
      ),
    );
  }
}
