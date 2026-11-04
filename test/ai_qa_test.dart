import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/ai/ai_client.dart';
import 'package:lifeos/ai/ai_models.dart';
import 'package:lifeos/ai/ai_provider.dart';
import 'package:lifeos/ai/ai_qa.dart';
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

String _json({String answer = '今天来得及，先写报告', List<Map<String, dynamic>>? plan}) {
  return jsonEncode(<String, dynamic>{
    'answer': answer,
    'plan': plan ?? <Map<String, dynamic>>[],
    'conflicts': <String>[],
  });
}

void main() {
  late AppDatabase db;
  late TaskRepository repo;
  final targetDay = DateTime(2026, 11, 4);
  final now = DateTime(2026, 11, 4, 9);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TaskRepository(db);
  });

  tearDown(() async => db.close());

  test('ask answers from the data and never writes', () async {
    final taskId = await repo.createTask(
      title: '写报告',
      urgency: 8,
      importance: 9,
      estimatedMinutes: 60,
    );
    final client = _FakeAiClient(_json());
    final service = AiQaService(client, repo, 'Test skill', now: () => now);

    final answer = await service.ask(
      provider: AiProviderConfig.deepSeek,
      apiKey: 'k',
      question: '今天来不来得及？',
      targetDay: targetDay,
    );

    expect(answer.text, contains('来得及'));
    expect(answer.slices, isEmpty);
    expect(answer.tasks, contains(taskId));
    expect(await repo.fetchSlicesForDay(targetDay), isEmpty);

    final user = client.messages!.last.content;
    expect(user, contains('写报告'));
    expect(user, contains('今天来不来得及'));
    expect(user, isNot(contains('Test skill')));
    expect(client.messages!.first.content, contains('Test skill'));
  });

  test('history is passed into the prompt', () async {
    await repo.createTask(title: '写报告');
    final client = _FakeAiClient(_json(answer: '下午三点有空'));
    final service = AiQaService(client, repo, 'Test skill', now: () => now);

    await service.ask(
      provider: AiProviderConfig.deepSeek,
      apiKey: 'k',
      question: '下午有空吗？',
      targetDay: targetDay,
      history: const [
        AiQaMessage(fromUser: true, text: '今天来不来得及？'),
        AiQaMessage(fromUser: false, text: '来得及'),
      ],
    );

    final user = client.messages!.last.content;
    expect(user, contains('今天来不来得及'));
    expect(user, contains('来得及'));
    expect(user, contains('下午有空吗'));
  });

  test('a plan in the answer is validated but not written', () async {
    final taskId = await repo.createTask(title: '写报告');
    final client = _FakeAiClient(_json(
      answer: '可以这样排',
      plan: [
        {
          'taskId': taskId,
          'startAt': '2026-11-04T10:00:00+08:00',
          'endAt': '2026-11-04T11:00:00+08:00',
          'reason': 'morning',
        }
      ],
    ));
    final service = AiQaService(client, repo, 'Test skill', now: () => now);

    final answer = await service.ask(
      provider: AiProviderConfig.deepSeek,
      apiKey: 'k',
      question: '今天怎么排？',
      targetDay: targetDay,
    );

    expect(answer.slices, hasLength(1));
    expect(answer.slices.single.taskId, taskId);
    expect(await repo.fetchSlicesForDay(targetDay), isEmpty);
  });

  test('no data still returns an answer without inventing tasks', () async {
    final client = _FakeAiClient(_json(answer: '目前没有任务，先记一件想做的事'));
    final service = AiQaService(client, repo, 'Test skill', now: () => now);

    final answer = await service.ask(
      provider: AiProviderConfig.deepSeek,
      apiKey: 'k',
      question: '今天来不来得及？',
      targetDay: targetDay,
    );

    expect(answer.text, isNotEmpty);
    expect(answer.slices, isEmpty);
    final user = client.messages!.last.content;
    expect(user, contains('(空)'));
  });

  test('invalid JSON surfaces AiPlanFormatException', () async {
    final service = AiQaService(
      _FakeAiClient('not json'),
      repo,
      'Test skill',
      now: () => now,
    );
    expect(
      () => service.ask(
        provider: AiProviderConfig.deepSeek,
        apiKey: 'k',
        question: 'x',
        targetDay: targetDay,
      ),
      throwsA(isA<AiPlanFormatException>()),
    );
  });
}
