import 'dart:convert';

import '../data/database.dart';

/// One suggested slice from the AI. `taskId` must exist in the context; the
/// validator drops unknown ids.
class AiSliceSuggestion {
  const AiSliceSuggestion({
    required this.taskId,
    required this.startAt,
    required this.endAt,
    required this.reason,
  });

  final String taskId;
  final DateTime startAt;
  final DateTime endAt;
  final String reason;

  Duration get duration => endAt.difference(startAt);

  static AiSliceSuggestion? tryParse(Map<String, dynamic> json) {
    final taskId = json['taskId'];
    final startRaw = json['startAt'];
    final endRaw = json['endAt'];
    if (taskId is! String || taskId.isEmpty) return null;
    if (startRaw is! String || endRaw is! String) return null;
    final start = DateTime.tryParse(startRaw);
    final end = DateTime.tryParse(endRaw);
    if (start == null || end == null) return null;
    return AiSliceSuggestion(
      taskId: taskId,
      startAt: start.toLocal(),
      endAt: end.toLocal(),
      reason: json['reason'] is String ? json['reason'] as String : '',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'taskId': taskId,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt.toIso8601String(),
        'reason': reason,
      };
}

class AiPlanFormatException implements Exception {
  const AiPlanFormatException(this.message);

  final String message;

  @override
  String toString() => 'AiPlanFormatException: $message';
}

/// Parsed AI plan (`{"answer": "...", "plan": [...], "conflicts": [...]}`).
class AiPlan {
  const AiPlan({
    required this.answer,
    required this.slices,
    required this.conflicts,
  });

  final String answer;
  final List<AiSliceSuggestion> slices;
  final List<String> conflicts;

  static AiPlan parse(String raw) {
    final text = _stripFences(raw);
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const AiPlanFormatException('AI 返回的不是合法 JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiPlanFormatException('AI 返回的 JSON 不是对象');
    }
    final rawSlices = decoded['plan'];
    if (rawSlices != null && rawSlices is! List) {
      throw const AiPlanFormatException('plan 字段不是数组');
    }
    final slices = <AiSliceSuggestion>[];
    if (rawSlices is List) {
      for (final item in rawSlices) {
        if (item is! Map<String, dynamic>) {
          throw const AiPlanFormatException('plan 里有非对象项');
        }
        final slice = AiSliceSuggestion.tryParse(item);
        if (slice == null) {
          throw const AiPlanFormatException('建议块缺 taskId/startAt/endAt 或时间非法');
        }
        slices.add(slice);
      }
    }
    final rawConflicts = decoded['conflicts'];
    final conflicts = <String>[];
    if (rawConflicts is List) {
      for (final item in rawConflicts) {
        if (item is String) conflicts.add(item);
      }
    }
    return AiPlan(
      answer: decoded['answer'] is String ? decoded['answer'] as String : '',
      slices: slices,
      conflicts: conflicts,
    );
  }

  static String _stripFences(String raw) {
    var text = raw.trim();
    if (!text.startsWith('```')) return text;
    final firstNewline = text.indexOf('\n');
    if (firstNewline != -1) {
      text = text.substring(firstNewline + 1);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    return text.trim();
  }
}

enum PlanIssueKind {
  unknownTask,
  invalidTime,
  crossDay,
  past,
  overlap,
  overAllocation,
}

enum PlanIssueSeverity { error, warning }

class PlanIssue {
  const PlanIssue({
    required this.index,
    required this.kind,
    required this.severity,
    required this.message,
  });

  final int index;
  final PlanIssueKind kind;
  final PlanIssueSeverity severity;
  final String message;

  bool get isError => severity == PlanIssueSeverity.error;
}

class PlanValidation {
  const PlanValidation({required this.validSlices, required this.issues});

  final List<AiSliceSuggestion> validSlices;
  final List<PlanIssue> issues;

  bool get hasWarnings => issues.any((issue) => !issue.isError);
}

/// Validated AI suggestion, ready for the UI to preview. Nothing is written
/// until [AiScheduleService.apply] is called explicitly.
class AiSuggestion {
  const AiSuggestion({
    required this.answer,
    required this.slices,
    required this.issues,
    required this.conflicts,
    required this.tasks,
    required this.targetDay,
  });

  final String answer;
  final List<AiSliceSuggestion> slices;
  final List<PlanIssue> issues;
  final List<String> conflicts;
  final Map<String, Record> tasks;
  final DateTime targetDay;

  bool get hasErrors => issues.any((issue) => issue.isError);
}
