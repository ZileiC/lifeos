import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/ai/ai_client.dart';
import 'package:lifeos/ai/ai_models.dart';
import 'package:lifeos/ai/ai_provider.dart';
import 'package:lifeos/ai/ai_schedule.dart';
import 'package:lifeos/ai/plan_validator.dart';
import 'package:lifeos/data/database.dart';
import 'package:lifeos/data/task_repository.dart';

class _FakeAiClient implements AiClient {
  _FakeAiClient(this.response);

  final String response;
  List<AiMessage>? messages;

  @override
  Future<AiCompletion> complete({
    required AiProviderConfig provider,
    required String apiKey,
    required List<AiMessage> messages,
    double temperature = 0.3,
    int maxTokens = 1500,
    String? reasoningEffort,
  }) async {
    this.messages = messages;
    return AiCompletion(content: response);
  }

  @override
  Future<List<AiModelInfo>> listModels({
    required AiProviderConfig provider,
    required String apiKey,
  }) async =>
      const <AiModelInfo>[];
}

Record _task({
  String id = 't1',
  int? urgency = 5,
  int? importance = 5,
  int? estimate = 60,
  String note = '',
}) {
  final now = DateTime(2026, 11, 1);
  return Record(
    id: id,
    title: 'Task $id',
    body: note,
    listId: null,
    pinned: false,
    allDay: true,
    dueAt: null,
    startAt: null,
    endAt: null,
    rrule: null,
    nextInstanceId: null,
    reminderOffsets: null,
    urgency: urgency,
    importance: importance,
    estimatedMinutes: estimate,
    color: null,
    recurrence: null,
    completedAt: null,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

DaySlice _slice({
  String id = 's1',
  String taskId = 't1',
  required DateTime start,
  required DateTime end,
}) {
  final now = DateTime(2026, 11, 1);
  return DaySlice(
    id: id,
    taskId: taskId,
    startAt: start,
    endAt: end,
    createdAt: now,
    updatedAt: now,
    deletedAt: null,
  );
}

AiSliceSuggestion _suggestion({
  String taskId = 't1',
  required DateTime start,
  required DateTime end,
}) =>
    AiSliceSuggestion(
      taskId: taskId,
      startAt: start,
      endAt: end,
      reason: 'test',
    );

String _json(List<Map<String, dynamic>> plan) => jsonEncode(<String, dynamic>{
      'answer': 'ok',
      'plan': plan,
      'conflicts': <String>[],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final targetDay = DateTime(2026, 11, 4);
  final now = DateTime(2026, 11, 4, 8);

  group('AiPlan.parse', () {
    test('parses a plain JSON plan', () {
      final plan = AiPlan.parse(_json([
        {
          'taskId': 't1',
          'startAt': DateTime(2026,11,4,9).toIso8601String(),
          'endAt': DateTime(2026,11,4,10).toIso8601String(),
          'reason': 'deep work',
        }
      ]));
      expect(plan.answer, 'ok');
      expect(plan.slices, hasLength(1));
      expect(plan.slices.first.taskId, 't1');
      expect(plan.slices.first.startAt.hour, 9);
    });

    test('strips a fenced code block', () {
      final plan = AiPlan.parse('```json\n${_json([])}\n```');
      expect(plan.slices, isEmpty);
    });

    test('rejects invalid JSON', () {
      expect(
        () => AiPlan.parse('not json'),
        throwsA(isA<AiPlanFormatException>()),
      );
    });

    test('rejects a malformed slice', () {
      expect(
        () => AiPlan.parse(_json([
          {'startAt': DateTime(2026,11,4,9).toIso8601String()}
        ])),
        throwsA(isA<AiPlanFormatException>()),
      );
    });
  });

  group('PlanValidator', () {
    test('accepts a valid target-day slice', () {
      final validation = PlanValidator(
        tasks: [_task()],
        existingSlices: const [],
        targetDay: targetDay,
        now: now,
      ).validate(AiPlan(
        answer: '',
        slices: [
          _suggestion(
            start: DateTime(2026, 11, 4, 9),
            end: DateTime(2026, 11, 4, 10),
          )
        ],
        conflicts: const [],
      ));
      expect(validation.validSlices, hasLength(1));
      expect(validation.issues, isEmpty);
    });

    test('drops an unknown task', () {
      final validation = PlanValidator(
        tasks: [_task()],
        existingSlices: const [],
        targetDay: targetDay,
        now: now,
      ).validate(AiPlan(
        answer: '',
        slices: [
          _suggestion(
            taskId: 'nope',
            start: DateTime(2026, 11, 4, 9),
            end: DateTime(2026, 11, 4, 10),
          )
        ],
        conflicts: const [],
      ));
      expect(validation.validSlices, isEmpty);
      expect(validation.issues.single.kind, PlanIssueKind.unknownTask);
      expect(validation.issues.single.isError, isTrue);
    });

    test('drops a past slice for today', () {
      final validation = PlanValidator(
        tasks: [_task()],
        existingSlices: const [],
        targetDay: targetDay,
        now: DateTime(2026, 11, 4, 10),
      ).validate(AiPlan(
        answer: '',
        slices: [
          _suggestion(
            start: DateTime(2026, 11, 4, 9),
            end: DateTime(2026, 11, 4, 10),
          )
        ],
        conflicts: const [],
      ));
      expect(validation.validSlices, isEmpty);
      expect(validation.issues.single.kind, PlanIssueKind.past);
    });

    test('drops a cross-day slice', () {
      final validation = PlanValidator(
        tasks: [_task()],
        existingSlices: const [],
        targetDay: targetDay,
        now: now,
      ).validate(AiPlan(
        answer: '',
        slices: [
          _suggestion(
            start: DateTime(2026, 11, 4, 23, 30),
            end: DateTime(2026, 11, 5, 0, 30),
          )
        ],
        conflicts: const [],
      ));
      expect(validation.validSlices, isEmpty);
      expect(validation.issues.single.kind, PlanIssueKind.crossDay);
    });

    test('warns on overlap but keeps the slice', () {
      final validation = PlanValidator(
        tasks: [_task()],
        existingSlices: [
          DaySliceWithTask(
            slice: _slice(
              start: DateTime(2026, 11, 4, 9),
              end: DateTime(2026, 11, 4, 10),
            ),
            task: _task(),
          )
        ],
        targetDay: targetDay,
        now: now,
      ).validate(AiPlan(
        answer: '',
        slices: [
          _suggestion(
            start: DateTime(2026, 11, 4, 9, 30),
            end: DateTime(2026, 11, 4, 10, 30),
          )
        ],
        conflicts: const [],
      ));
      expect(validation.validSlices, hasLength(1));
      final overlapIssues = validation.issues
          .where((issue) => issue.kind == PlanIssueKind.overlap)
          .toList();
      expect(overlapIssues, hasLength(1));
      expect(overlapIssues.single.isError, isFalse);
    });

    test('warns on over-allocation', () {
      final validation = PlanValidator(
        tasks: [_task()],
        existingSlices: [
          DaySliceWithTask(
            slice: _slice(
              start: DateTime(2026, 11, 4, 9),
              end: DateTime(2026, 11, 4, 9, 40),
            ),
            task: _task(),
          )
        ],
        targetDay: targetDay,
        now: now,
      ).validate(AiPlan(
        answer: '',
        slices: [
          _suggestion(
            start: DateTime(2026, 11, 4, 14),
            end: DateTime(2026, 11, 4, 14, 30),
          )
        ],
        conflicts: const [],
      ));
      expect(validation.issues.single.kind, PlanIssueKind.overAllocation);
      expect(validation.issues.single.isError, isFalse);
    });
  });

  group('AiScheduleService', () {
    late AppDatabase db;
    late TaskRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = TaskRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('suggest validates, captures the prompt, and does not write',
        () async {
      final taskId = await repo.createTask(
        title: '写报告',
        note: 'secret note',
        urgency: 8,
        importance: 9,
        estimatedMinutes: 60,
      );
      final client = _FakeAiClient(_json([
        {
          'taskId': taskId,
          'startAt': DateTime(2026,11,4,9).toIso8601String(),
          'endAt': DateTime(2026,11,4,10).toIso8601String(),
          'reason': 'morning deep work',
        }
      ]));
      final service = AiScheduleService(
        client,
        repo,
        'Test skill v2',
        now: () => now,
      );

      final suggestion = await service.suggest(
        provider: AiProviderConfig.deepSeek,
        apiKey: 'test',
        targetDay: targetDay,
      );

      expect(suggestion.slices, hasLength(1));
      expect(suggestion.answer, 'ok');
      expect(suggestion.tasks, contains(taskId));
      expect(await repo.watchSlicesForDay(targetDay).first, isEmpty);

      final system = client.messages!.first.content;
      final user = client.messages!.last.content;
      expect(system, contains('Test skill v2'));
      expect(system, contains('taskId'));
      expect(user, contains('写报告'));
      expect(user, contains(taskId));
      expect(user, isNot(contains('secret note')));
    });

    test('apply writes only the confirmed slices and never completes',
        () async {
      final taskId = await repo.createTask(
        title: '写报告',
        urgency: 8,
        importance: 9,
        estimatedMinutes: 60,
      );
      final client = _FakeAiClient(_json([
        {
          'taskId': taskId,
          'startAt': DateTime(2026,11,4,9).toIso8601String(),
          'endAt': DateTime(2026,11,4,10).toIso8601String(),
          'reason': 'morning',
        },
        {
          'taskId': taskId,
          'startAt': DateTime(2026,11,4,14).toIso8601String(),
          'endAt': DateTime(2026,11,4,15).toIso8601String(),
          'reason': 'afternoon',
        },
      ]));
      final service = AiScheduleService(
        client,
        repo,
        'Test skill v2',
        now: () => now,
      );
      final suggestion = await service.suggest(
        provider: AiProviderConfig.deepSeek,
        apiKey: 'test',
        targetDay: targetDay,
      );
      expect(suggestion.slices, hasLength(2));

      final ids = await service.apply(
        suggestion: suggestion,
        slices: [suggestion.slices.first],
      );

      expect(ids, hasLength(1));
      final written = await repo.watchSlicesForDay(targetDay).first;
      expect(written, hasLength(1));
      expect(written.single.slice.taskId, taskId);
      final task = await repo.watchActiveTasks().first;
      expect(task.single.completedAt, isNull);
    });

    test('invalid JSON surfaces AiPlanFormatException', () async {
      await repo.createTask(title: '写报告');
      final service = AiScheduleService(
        _FakeAiClient('not json'),
        repo,
        'Test skill v2',
        now: () => now,
      );
      expect(
        () => service.suggest(
          provider: AiProviderConfig.deepSeek,
          apiKey: 'test',
          targetDay: targetDay,
        ),
        throwsA(isA<AiPlanFormatException>()),
      );
    });

    test('unknown task is dropped and nothing is written', () async {
      await repo.createTask(title: '写报告');
      final client = _FakeAiClient(_json([
        {
          'taskId': 'invented',
          'startAt': DateTime(2026,11,4,9).toIso8601String(),
          'endAt': DateTime(2026,11,4,10).toIso8601String(),
          'reason': 'x',
        }
      ]));
      final service = AiScheduleService(
        client,
        repo,
        'Test skill v2',
        now: () => now,
      );
      final suggestion = await service.suggest(
        provider: AiProviderConfig.deepSeek,
        apiKey: 'test',
        targetDay: targetDay,
      );
      expect(suggestion.slices, isEmpty);
      expect(suggestion.issues.single.kind, PlanIssueKind.unknownTask);
      expect(await repo.watchSlicesForDay(targetDay).first, isEmpty);
    });
  });

  test('bundled scheduling skill is v2', () async {
    final skill = await rootBundle.loadString('assets/skill/scheduling.md');
    expect(skill, contains('Version: 2'));
    expect(skill, contains('Sources'));
  });
}
