import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local notification scheduling for DDL reminders (v0.1.3 L2).
///
/// Scheduling choice — exact alarms (zonedSchedule with
/// [AndroidScheduleMode.exactAllowWhileIdle]) over WorkManager:
/// * The acceptance test requires a 1-minute lead to fire on the lock screen.
///   WorkManager's minimum periodic interval is 15 minutes and it is batched
///   by the OS, so it cannot satisfy the hard requirement.
/// * Exact alarms (USE_EXACT_ALARM / SCHEDULE_EXACT_ALARM on Android 12+)
///   fire precisely even when the app is killed.
/// * Fallback chain when permissions are denied: schedule inexact, surface an
///   in-app banner, and offer a jump to system settings.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize the plugin and timezone data (call once from main()).
  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onTapped,
    );
    _initialized = true;
  }

  /// True once [init] has completed. All scheduling entry points no-op when
  /// false so repository writes are safe in tests / before app start.
  bool get isReady => _initialized;

  /// Notification tap handler: deep link is simplified to opening the app's
  /// main screen (the record is right there in the inbox/today list).
  static void _onTapped(NotificationResponse response) {
    // Payload carries the record id; opening the main screen is the
    // simplified deep link allowed by the work order.
  }

  /// True when the OS will let us schedule exact alarms.
  Future<bool> get canScheduleExact async {
    if (!_initialized) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    // Notifications permission (Android 13+).
    final enabled = await android.areNotificationsEnabled() ?? false;
    if (!enabled) return false;
    // Exact alarm permission (Android 12+; older versions grant by default).
    return await android.canScheduleExactNotifications() ?? false;
  }

  /// Request the notification permission; returns whether it is granted.
  /// (Exact-alarm permission cannot be requested in-app on Android 14+;
  /// users must toggle it in system settings — the banner links there.)
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// (Re)schedule all reminder instants for a record.
  /// Ids are derived from the record id hash + offset so re-scheduling
  /// replaces previous alarms instead of stacking. No-op before [init].
  Future<ScheduleResult> scheduleForRecord({
    required String recordId,
    required String title,
    required String? timeLabel,
    required List<int> offsets,
    required List<DateTime> instants,
  }) async {
    if (!_initialized) {
      return ScheduleResult(exact: false, scheduled: 0);
    }
    // Cancel any previously scheduled notifications for this record first.
    await cancelForRecord(recordId);

    final exact = await canScheduleExact;
    var scheduled = 0;
    for (var i = 0; i < instants.length; i++) {
      final offset = offsets.length > i ? offsets[i] : offsets.first;
      final id = notificationId(recordId, offset);
      final body = timeLabel == null || timeLabel.isEmpty
          ? title
          : '$timeLabel $title';
      await _scheduleOne(
        id: id,
        body: body,
        payload: recordId,
        at: instants[i],
        exact: exact,
      );
      scheduled++;
    }
    return ScheduleResult(exact: exact, scheduled: scheduled);
  }

  Future<void> _scheduleOne({
    required int id,
    required String body,
    required String payload,
    required DateTime at,
    required bool exact,
  }) async {
    final tzAt = tz.TZDateTime.from(at, tz.local);
    const androidDetails = AndroidNotificationDetails(
      'ddl_reminders', // channel id
      '到期提醒', // channel name (user-facing, stays Chinese per L1)
      channelDescription: '任务到期前的提前提醒',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.zonedSchedule(
      id: id,
      title: 'LifeOS 提醒',
      body: body,
      scheduledDate: tzAt,
      notificationDetails: details,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  /// Cancel all pending notifications for a record across all known offsets.
  /// No-op before [init] (nothing can be pending).
  Future<void> cancelForRecord(
    String recordId, {
    List<int> offsets = kAllReminderOffsets,
  }) async {
    if (!_initialized) return;
    for (final offset in offsets) {
      await _plugin.cancel(id: notificationId(recordId, offset));
    }
  }

  /// Stable notification id from record UUID + offset. Hash collisions are
  /// possible in theory; cancel-then-schedule keeps state consistent.
  static int notificationId(String recordId, int offset) =>
      (recordId.hashCode ^ (offset * 2654435761)) & 0x7FFFFFFF;
}

/// All preset offsets, used for the defensive cancel sweep.
const List<int> kAllReminderOffsets = [0, 5, 15, 30, 60, 120, 1440];

/// Result of a scheduling pass, used for the in-app permission banner.
class ScheduleResult {
  ScheduleResult({required this.exact, required this.scheduled});

  /// False when exact-alarm/notification permission is missing and we fell
  /// back to inexact scheduling.
  final bool exact;
  final int scheduled;
}
