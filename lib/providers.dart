import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'data/task_repository.dart';

/// Global database singleton. Tests override this with an in-memory database.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(databaseProvider));
});

final tasksProvider = StreamProvider<List<Record>>((ref) {
  return ref.watch(taskRepositoryProvider).watchActiveTasks();
});

final allSlicesProvider = StreamProvider<List<DaySlice>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAllSlices();
});

class SelectedDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => _today();

  void set(DateTime date) => state = DateTime(date.year, date.month, date.day);

  void shift(int days) => state = state.add(Duration(days: days));

  void today() => state = _today();

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

final selectedDayProvider =
    NotifierProvider<SelectedDayNotifier, DateTime>(SelectedDayNotifier.new);

final daySlicesProvider =
    StreamProvider.family<List<DaySliceWithTask>, DateTime>((ref, day) {
  return ref.watch(taskRepositoryProvider).watchSlicesForDay(day);
});
