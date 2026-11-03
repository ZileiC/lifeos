import '../data/database.dart';
import '../data/task_repository.dart';
import 'ai_client.dart';
import 'ai_models.dart';
import 'ai_provider.dart';
import 'plan_validator.dart';
import 'scheduler_prompt.dart';

/// Orchestrates one AI scheduling proposal. It never writes by itself: the UI
/// must call [apply] with the user-confirmed (possibly edited) slices.
class AiScheduleService {
  AiScheduleService(
    this._client,
    this._repository,
    this._skill, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AiClient _client;
  final TaskRepository _repository;
  final String _skill;
  final DateTime Function() _now;

  Future<AiSuggestion> suggest({
    required AiProviderConfig provider,
    required String apiKey,
    required DateTime targetDay,
  }) async {
    final now = _now();
    final dayStart = DateTime(targetDay.year, targetDay.month, targetDay.day);
    final tasks = await _repository.watchActiveTasks().first;
    final targetSlices = await _repository.watchSlicesForDay(targetDay).first;
    final upcoming = await _repository.watchSlicesBetween(
      dayStart.add(const Duration(days: 1)),
      dayStart.add(const Duration(days: 8)),
    ).first;

    final prompt = SchedulerPrompt(
      skill: _skill,
      now: now,
      targetDay: targetDay,
      tasks: tasks,
      targetDaySlices: targetSlices,
      upcomingSlices: upcoming,
    );
    final completion = await _client.complete(
      provider: provider,
      apiKey: apiKey,
      messages: prompt.build(),
      temperature: 0.3,
      maxTokens: 1500,
    );
    final plan = AiPlan.parse(completion.content);
    final validation = PlanValidator(
      tasks: tasks,
      existingSlices: <DaySliceWithTask>[...targetSlices, ...upcoming],
      targetDay: targetDay,
      now: now,
    ).validate(plan);

    return AiSuggestion(
      answer: plan.answer,
      slices: validation.validSlices,
      issues: validation.issues,
      conflicts: plan.conflicts,
      tasks: <String, Record>{for (final task in tasks) task.id: task},
      targetDay: targetDay,
    );
  }

  /// Writes the user-confirmed slices (already validated/edited by the user).
  /// The method is explicit: no automatic write on [suggest]. Completion is
  /// never touched.
  Future<List<String>> apply({
    required AiSuggestion suggestion,
    required List<AiSliceSuggestion> slices,
  }) async {
    final ids = <String>[];
    for (final slice in slices) {
      if (!suggestion.tasks.containsKey(slice.taskId)) continue;
      if (!slice.endAt.isAfter(slice.startAt)) continue;
      ids.add(await _repository.addSlice(
        taskId: slice.taskId,
        startAt: slice.startAt,
        endAt: slice.endAt,
      ));
    }
    return ids;
  }
}
