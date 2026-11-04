import '../data/database.dart';
import '../data/task_repository.dart';
import 'ai_client.dart';

/// Builds the system/user messages for the day-scheduling call. The system
/// prompt is the distilled scheduling skill (v2) plus the strict JSON contract;
/// the user message is the concrete context (tasks, target-day slices, next 7
/// days).
class SchedulerPrompt {
  const SchedulerPrompt({
    required this.skill,
    required this.now,
    required this.targetDay,
    required this.tasks,
    required this.targetDaySlices,
    required this.upcomingSlices,
  });

  final String skill;
  final DateTime now;
  final DateTime targetDay;
  final List<Record> tasks;
  final List<DaySliceWithTask> targetDaySlices;
  final List<DaySliceWithTask> upcomingSlices;

  List<AiMessage> build() => <AiMessage>[
        AiMessage(role: 'system', content: _system()),
        AiMessage(role: 'user', content: _user()),
      ];

  String _system() {
    return '''
$skill

You are the scheduling assistant inside the LifeOS phone app. Apply the skill above.

Output ONLY one JSON object with this exact shape, no markdown, no prose outside it:
{
  "answer": "short Chinese explanation for the user",
  "plan": [
    {"taskId": "...", "startAt": "YYYY-MM-DDTHH:mm:ss+08:00", "endAt": "YYYY-MM-DDTHH:mm:ss+08:00", "reason": "short Chinese reason"}
  ],
  "conflicts": ["short Chinese conflict descriptions, empty array when none"]
}

Hard requirements:
- taskId MUST come from the task list in the user message. Never invent tasks.
- Every plan item must start and end inside the target day; do not cross midnight.
- Never schedule a block that starts in the past relative to "now".
- Respect fixed commitments, hard ddl, the 60-70% day cap and the 1.25-1.5x buffer.
- Same task keeps its persistent color; do not invent a per-day color.
- Never write or infer completion; the phone only plans.
- If the ddl cannot be met, explain the shortfall and offer 2-3 options in "conflicts".
- Use local times with the +08:00 offset. Keep the answer short.
''';
  }

  String _user() {
    final buffer = StringBuffer()
      ..writeln('当前时间：${now.toIso8601String()}')
      ..writeln('目标日：${targetDay.year}-${_two(targetDay.month)}-${_two(targetDay.day)}')
      ..writeln()
      ..writeln('任务列表（taskId | 标题 | U/I | ddl | 预估 | 固定 | 模式）：');
    if (tasks.isEmpty) {
      buffer.writeln('(空)');
    } else {
      for (final task in tasks.take(50)) {
        buffer.writeln('- ${task.id} | ${task.title} | U:${task.urgency ?? '-'} I:${task.importance ?? '-'} '
            '| start:${task.startAt == null ? '-' : task.startAt!.toIso8601String()} '
            '| ddl:${task.dueAt == null ? '-' : task.dueAt!.toIso8601String()} '
            '| est:${task.estimatedMinutes == null ? '-' : '${task.estimatedMinutes}m'} '
            '| pinned:${task.pinned ? 'yes' : 'no'} '
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
      ..writeln('未来 7 天已有日片（用于判断负载和缓冲）：');
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
      ..writeln('请为目标日生成一个可执行、留有余量的日片建议。只输出 JSON。');
    return buffer.toString();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
