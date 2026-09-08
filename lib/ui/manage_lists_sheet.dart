import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// List management: create / rename / delete.
Future<void> showManageListsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ManageListsSheet(),
  );
}

class _ManageListsSheet extends ConsumerStatefulWidget {
  const _ManageListsSheet();

  @override
  ConsumerState<_ManageListsSheet> createState() => _ManageListsSheetState();
}

class _ManageListsSheetState extends ConsumerState<_ManageListsSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lists = ref.watch(listsProvider).value ?? const [];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('管理清单',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            // Create input.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(hintText: '新清单名称'),
                      textInputAction: TextInputAction.done,
                      onSubmitted: _create,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _create(_controller.text),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (lists.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('还没有清单，先建一个吧',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final l in lists)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(l.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: '重命名',
                              onPressed: () => _rename(l.id, l.name),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline_rounded,
                                  size: 20, color: theme.colorScheme.error),
                              tooltip: '删除（其中记录回到收件箱）',
                              onPressed: () => _delete(l.id, l.name),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _create(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;
    await ref.read(repositoryProvider).createList(n);
    _controller.clear();
  }

  Future<void> _rename(String id, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名清单'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(repositoryProvider).renameList(id, name);
    }
  }

  Future<void> _delete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「$name」？'),
        content: const Text('清单里的记录不会被删，会回到收件箱。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(repositoryProvider).deleteList(id);
      // If the deleted list is selected, fall back to all.
      final sel = ref.read(selectedListProvider);
      if (sel == id) ref.read(selectedListProvider.notifier).set(null);
    }
  }
}
