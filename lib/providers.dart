import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'data/repository.dart';

/// 全局数据库单例
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 仓库
final repositoryProvider = Provider<RecordRepository>(
    (ref) => RecordRepository(ref.watch(databaseProvider)));

/// 当前视图
class ViewKindNotifier extends Notifier<ViewKind> {
  @override
  ViewKind build() => ViewKind.inbox;
  void set(ViewKind kind) => state = kind;
}

final viewKindProvider =
    NotifierProvider<ViewKindNotifier, ViewKind>(ViewKindNotifier.new);

/// 当前选中的清单（null = 全部）
class SelectedListNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? listId) => state = listId;
}

final selectedListProvider =
    NotifierProvider<SelectedListNotifier, String?>(SelectedListNotifier.new);

/// 当前视图的记录流
final recordsProvider = StreamProvider<List<RecordWithItems>>((ref) {
  final repo = ref.watch(repositoryProvider);
  final kind = ref.watch(viewKindProvider);
  final listId = ref.watch(selectedListProvider);
  return repo.watchRecords(kind: kind, listId: listId);
});

/// 清单流
final listsProvider = StreamProvider<List<ListRecord>>((ref) {
  return ref.watch(repositoryProvider).watchLists();
});
