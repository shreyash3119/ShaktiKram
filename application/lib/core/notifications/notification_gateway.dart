import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_planner.dart';

/// The phone's notification system. [LocalNotificationGateway] is the real one; tests and unconfigured runs use
/// [NoNotificationGateway].
abstract class NotificationGateway {
  Future<void> init();

  /// Asks Android for permission to show notifications (Android 13+). Returns whether they are allowed.
  Future<bool> requestPermission();

  /// Replaces everything pending with [reminders].
  Future<void> replaceAll(List<PlannedReminder> reminders);

  Future<void> showNow(String title, String body);
}

class NoNotificationGateway implements NotificationGateway {
  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async {}

  @override
  Future<void> showNow(String title, String body) async {}
}

final notificationGatewayProvider = Provider<NotificationGateway>((ref) => NoNotificationGateway());

class LocalNotificationGateway implements NotificationGateway {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(await _localLocation());
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    for (final c in ReminderChannel.values) {
      // High importance: sound and a pop-up (heads-up) banner, like other apps.
      await _android?.createNotificationChannel(
        AndroidNotificationChannel(c.id, c.label, description: c.description, importance: Importance.high),
      );
    }
    _ready = true;
  }

  /// The phone's own time zone. If it cannot be read, a zone with the same current offset is used, so reminders still
  /// fire at the right clock time.
  Future<tz.Location> _localLocation() async {
    try {
      // Older versions of the plugin return the name as a String, newer ones an object with an `identifier`.
      final dynamic zone = await FlutterTimezone.getLocalTimezone();
      final name = zone is String ? zone : (zone as dynamic).identifier as String;
      return tz.getLocation(name);
    } catch (e) {
      debugPrint('Time zone lookup failed, matching by offset: $e');
      final offset = DateTime.now().timeZoneOffset;
      for (final l in tz.timeZoneDatabase.locations.values) {
        if (l.timeZone(DateTime.now().millisecondsSinceEpoch).offset == offset.inMilliseconds) return l;
      }
      return tz.UTC;
    }
  }

  NotificationDetails _details(ReminderChannel c) => NotificationDetails(
    android: AndroidNotificationDetails(
      c.id,
      c.label,
      channelDescription: c.description,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    ),
  );

  @override
  Future<bool> requestPermission() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    await init();
    await _plugin.cancelAll();
    for (final r in reminders) {
      try {
        await _plugin.zonedSchedule(
          r.id,
          r.title,
          r.body,
          tz.TZDateTime.from(r.at, tz.local),
          _details(r.channel),
          // Not exact: no special "alarms" permission is needed; Android may deliver a few minutes late.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: switch (r.repeat) {
            ReminderRepeat.none => null,
            ReminderRepeat.daily => DateTimeComponents.time,
            ReminderRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
          },
        );
      } catch (e) {
        debugPrint('Could not schedule reminder ${r.id}: $e');
      }
    }
  }

  @override
  Future<void> showNow(String title, String body) async {
    await init();
    await _plugin.show(9000, title, body, _details(ReminderChannel.test));
  }
}
