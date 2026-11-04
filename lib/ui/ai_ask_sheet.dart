import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_models.dart';
import '../ai/ai_qa.dart';
import '../ai/ai_schedule.dart';
import '../providers.dart';
import 'ai_suggestion_sheet.dart';

/// Read-only Q&A sheet. The AI answers from the real data; it never writes.
/// If the answer carries a plan, "按这个排" opens the normal suggestion preview
/// and only a confirm writes slices.
class AiAskSheet extends ConsumerStatefulWidget {
  const AiAskSheet({super.key, required this.targetDay});

  final DateTime targetDay;

  @override
  ConsumerState<AiAskSheet> createState() => _AiAskSheetState();
}

class _AiAskSheetState extends ConsumerState<AiAskSheet> {
  final TextEditingController _controller = TextEditingController();
  final List<AiQaMessage> _messages = <AiQaMessage>[];
  AiQaAnswer? _lastAnswer;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<AiQaMessage> get _history {
    final turns = <AiQaMessage>[];
    for (final message in _messages) {
      turns.add(message);
    }
    // Keep the last 5 turns (user+assistant pairs) for the prompt.
    if (turns.length > 10) return turns.sublist(turns.length - 10);
    return turns;
  }

  Future<void> _ask() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _loading) return;

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
      setState(() => _error = '先在 AI 设置里填 API key');
      return;
    }

    final history = _history;
    setState(() {
      _loading = true;
      _error = null;
      _controller.clear();
      _messages.add(AiQaMessage(fromUser: true, text: question));
      _lastAnswer = null;
    });

    try {
      final skill = await ref.read(schedulingSkillProvider.future);
      final service = AiQaService(
        ref.read(aiClientProvider),
        ref.read(taskRepositoryProvider),
        skill,
      );
      final answer = await service.ask(
        provider: provider,
        apiKey: apiKey,
        question: question,
        targetDay: widget.targetDay,
        history: history,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(AiQaMessage(fromUser: false, text: answer.text));
        _lastAnswer = answer;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'AI 问答失败：$error';
      });
    }
  }

  Future<void> _convertToSchedule(AiQaAnswer answer) async {
    final suggestion = AiSuggestion(
      answer: answer.text,
      slices: answer.slices,
      issues: const <PlanIssue>[],
      conflicts: answer.conflicts,
      tasks: answer.tasks,
      targetDay: widget.targetDay,
    );
    final confirmed = await showModalBottomSheet<List<AiSliceSuggestion>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AiSuggestionSheet(suggestion: suggestion),
    );
    if (!mounted || confirmed == null || confirmed.isEmpty) return;
    final skill = await ref.read(schedulingSkillProvider.future);
    final service = AiScheduleService(
      ref.read(aiClientProvider),
      ref.read(taskRepositoryProvider),
      skill,
    );
    await service.apply(suggestion: suggestion, slices: confirmed);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已写入 ${confirmed.length} 块日片')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.forum_outlined,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('问 AI', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  Text(
                    '只读 · 不写库',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          '问点具体的，比如：今天来不来得及？下午有空吗？明天怎么排？',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final isLast =
                            index == _messages.length - 1 && !_loading;
                        return _MessageBubble(
                          message: message,
                          answer: message.fromUser ? null : _lastAnswer,
                          onConvert: isLast && (_lastAnswer?.slices.isNotEmpty ?? false)
                              ? () => _convertToSchedule(_lastAnswer!)
                              : null,
                        );
                      },
                    ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                12,
                8 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('ask-input'),
                      controller: _controller,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _ask(),
                      decoration: const InputDecoration(
                        hintText: '问今天来不来得及…',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('ask-send'),
                    onPressed: _loading ? null : _ask,
                    icon: const Icon(Icons.arrow_upward, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.answer, this.onConvert});

  final AiQaMessage message;
  final AiQaAnswer? answer;
  final VoidCallback? onConvert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromUser = message.fromUser;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: fromUser
              ? theme.colorScheme.primary.withValues(alpha: 0.14)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: fromUser
                ? theme.colorScheme.primary.withValues(alpha: 0.28)
                : theme.colorScheme.outline.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.text,
              style: theme.textTheme.bodyMedium,
            ),
            if (!fromUser && (answer?.conflicts.isNotEmpty ?? false)) ...[
              const SizedBox(height: 6),
              ...answer!.conflicts.map(
                (line) => Text(
                  '• $line',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
            if (!fromUser && onConvert != null) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                key: const Key('ask-convert'),
                onPressed: onConvert,
                icon: const Icon(Icons.event_available, size: 16),
                label: const Text('按这个排'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
