import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Best-effort backup of the pre-C′ (v4) database before the v4 -> v5
/// migration. App startup must never be blocked by a backup failure.
class DatabaseBackup {
  const DatabaseBackup._();

  static const String databaseFileName = 'lifeos.sqlite';
  static const String backupFileName = 'lifeos-v4-backup.sqlite';

  static Future<void> ensureV4Backup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final separator = Platform.pathSeparator;
      final source = File('${dir.path}$separator$databaseFileName');
      if (!await source.exists()) return;
      final target = File('${dir.path}$separator$backupFileName');
      if (await target.exists()) return;
      await source.copy(target.path);
    } catch (_) {
      // Best-effort only.
    }
  }
}
