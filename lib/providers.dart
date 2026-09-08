import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'data/repository.dart';

/// Global database singleton.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Repository.
final repositoryProvider = Provider<RecordRepository>(
    (ref) => RecordRepository(ref.watch(databaseProvider)));

/// Current view kind.
class ViewKindNotifier extends Notifier<ViewKind> {
  @override
  ViewKind build() => ViewKind.inbox;
  void set(ViewKind kind) => state = kind;
}

final viewKindProvider =
    NotifierProvider<ViewKindNotifier, ViewKind>(ViewKindNotifier.new);

/// Currently selected list (null = all).
class SelectedListNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? listId) => state = listId;
}

final selectedListProvider =
    NotifierProvider<SelectedListNotifier, String?>(SelectedListNotifier.new);

/// Current view kind.的记录流
final recordsProvider = StreamProvider<List<RecordWithItems>>((ref) {
  final repo = ref.watch(repositoryProvider);
  final kind = ref.watch(viewKindProvider);
  final listId = ref.watch(selectedListProvider);
  return repo.watchRecords(kind: kind, listId: listId);
});

/// List stream.
final listsProvider = StreamProvider<List<ListRecord>>((ref) {
  return ref.watch(repositoryProvider).watchLists();
});
