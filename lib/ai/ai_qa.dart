import '../data/database.dart';
import '../data/task_repository.dart';
import 'ai_client.dart';
import 'ai_models.dart';
import 'ai_provider.dart';
import 'plan_validator.dart';

/// One Q&A turn. Kept in memory only; the latest turns are passed to the AI.
class AiQaMessage {
  const AiQaMessage({required this.fromUser, required this.text});

  final bool fromUser;
  final String text;
}

class AiQaAnswer {
  const AiQaAnswer({
    required this.text,
    required this.slices,
    required this.conflicts,
    required this.tasks,
  });

  final String text;
  final List<AiSliceSuggestion> slices;
  final List<String> conflicts;
  final Map<String, Record> tasks;
}

/// Read-only Q&A over the user's real data. It never writes tasks or slices;
/// if the answer contains a plan, the UI may route it through the normal
/// suggestion preview/confirm flow.
class AiQaService {
  AiQaService(
    this._client,
    this._repository,
    this._skill, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AiClient _client;
  final TaskRepository _repository;
  final String _skill;
  final DateTime Function() _now;

  Future<AiQaAnswer> ask({
    required AiProviderConfig provider,
    required String apiKey,
    required String question,
    required DateTime targetDay,
    List<AiQaMessage> history = const <AiQaMessage>[],
  }) async {
    final now = _now();
    final dayStart = DateTime(targetDay.year, targetDay.month, targetDay.day);
    final tasks = await _repository.fetchActiveTasks();
    final targetSlices = await _repository.fetchSlicesForDay(targetDay);
    final upcoming = await _repository.fetchSlicesBetween(
      dayStart.add(const Duration(days: 1)),
      dayStart.add(const Duration(days: 8)),
    );

    final prompt = _QaPrompt(
      skill: _skill,
      now: now,
      targetDay: targetDay,
      tasks: tasks,
      targetDaySlices: targetSlices,
      upcomingSlices: upcoming,
      question: question,
      history: history,
    );
    final completion = await _client.complete(
      provider: provider,
      apiKey: apiKey,
      messages: prompt.build(),
      temperature: 0.3,
      maxTokens: 1200,
    );
    final plan = AiPlan.parse(completion.content);
    final validation = PlanValidator(
      tasks: tasks,
      existingSlices: <DaySliceWithTask>[...targetSlices, ...upcoming],
      targetDay: targetDay,
      now: now,
    ).validate(plan);

    return AiQaAnswer(
      text: plan.answer.isEmpty ? '（AI 没有返回回答）' : plan.answer,
      slices: validation.validSlices,
      conflicts: <String>[
        ...plan.conflicts,
        ...validation.issues.map((issue) => issue.message),
      ],
      tasks: <String, Record>{for (final task in tasks) task.id: task},
    );
  }
}

class _QaPrompt {
  const _QaPrompt({
    required this.skill,
    required this.now,
    required this.targetDay,
    required this.tasks,
    required this.targetDaySlices,
    required this.upcomingSlices,
    required this.question,
    required this.history,
  });

  final String skill;
  final DateTime now;
  final DateTime targetDay;
  final List<Record> tasks;
  final List<DaySliceWithTask> targetDaySlices;
  final List<DaySliceWithTask> upcomingSlices;
  final String question;
  final List<AiQaMessage> history;

  List<AiMessage> build() => <AiMessage>[
        AiMessage(role: 'system', content: _system()),
        AiMessage(role: 'user', content: _user()),
      ];

  String _system() {
    return '''
$skill

You are the LifeOS day-planning Q&A assistant inside the phone app. Answer the user's question from the data below (tasks, existing slices, weekly fixed items, DDL, estimates, current time).

Rules:
- Read-only: never claim you wrote, moved or completed anything. You may propose a plan, but the user must confirm it in the preview.
- Answer in Chinese, short and concrete: "来不来得及 / 今天怎么排 / 下午有空吗" style.
- If the data is empty or insufficient, say so plainly; do not invent tasks or times.
- If a plan would help, include it in "plan" using taskIds from the task list only.
- Use local times with the +08:00 offset; blocks must stay inside the target day.

Output ONLY one JSON object:
{
  "answer": "short Chinese answer",
  "plan": [{"taskId": "...", "startAt": "...", "endAt": "...", "reason": "..."}],
  "conflicts": ["short Chinese conflicts, empty array when none"]
}
"plan" may be an empty array when the question does not need one.
''';
  }

  String _user() {
    final buffer = StringBuffer()
      ..writeln('当前时间：${now.toIso8601String()}')
      ..writeln('目标日：${targetDay.year}-${_two(targetDay.month)}-${_two(targetDay.day)}')
      ..writeln()
      ..writeln('任务列表：');
    if (tasks.isEmpty) {
      buffer.writeln('(空)');
    } else {
      for (final task in tasks.take(50)) {
        buffer.writeln('- ${task.id} | ${task.title} | U:${task.urgency ?? '-'} I:${task.importance ?? '-'} '
            '| start:${task.startAt == null ? '-' : task.startAt!.toIso8601String()} '
            '| ddl:${task.dueAt == null ? '-' : task.dueAt!.toIso8601String()} '
            '| est:${task.estimatedMinutes == null ? '-' : '${task.estimatedMinutes}m'} '
            '| weekly:${task.recurrence == null ? 'no' : 'yes'}');
      }
    }
    buffer
      ..writeln()
      ..writeln('目标日已有日片：');
    if (targetDaySlices.isEmpty) {
      buffer.writeln('(空)');
    } else {
      for (final item in targetDaySlices) {
        buffer.writeln('- ${item.slice.taskId} | ${item.task.title} | '
            '${item.slice.startAt.toIso8601String()} → ${item.slice.endAt.toIso8601String()}');
      }
    }
    buffer
      ..writeln()
      ..writeln('未来 7 天已有日片：');
    if (upcomingSlices.isEmpty) {
      buffer.writeln('(空)');
    } else {
      for (final item in upcomingSlices.take(100)) {
        buffer.writeln('- ${item.slice.taskId} | ${item.task.title} | '
            '${item.slice.startAt.toIso8601String()} → ${item.slice.endAt.toIso8601String()}');
      }
    }
    buffer
      ..writeln()
      ..writeln('对话历史（最近 5 轮）：');
    if (history.isEmpty) {
      buffer.writeln('(空)');
    } else {
      for (final message in history) {
        buffer.writeln('${message.fromUser ? '用户' : '助手'}: ${message.text}');
      }
    }
    buffer
      ..writeln()
      ..writeln('用户问题：$question')
      ..writeln('只输出 JSON。');
    return buffer.toString();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
