/// The daily reading reminder: local notifications, scheduled on the phone.
/// Nothing leaves the phone.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// One reminder: when (local time) and what it says.
class Reminder {
  const Reminder({required this.at, required this.title, required this.body});

  final DateTime at;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) => other is Reminder && other.at == at && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(at, title, body);
}

/// The phone's notifications (tests replace it).
abstract interface class Reminders {
  /// Asks for permission to notify (Android 13+). True if notifications
  /// can be shown.
  Future<bool> requestPermission();

  /// Replaces every scheduled reminder with [reminders] (none: cancel all).
  /// [channelName] is the name Android shows in the app's notification
  /// settings, in the interface language.
  Future<void> replace(List<Reminder> reminders, {required String channelName});
}

/// [Reminders] through flutter_local_notifications.
class LocalReminders implements Reminders {
  LocalReminders([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;

  static const _channel = 'daily_reading';

  /// The monochrome book drawn in the status bar (res/drawable).
  static const _icon = 'ic_stat_rafiq';

  Future<void> _init() => _ready ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_icon),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      )
      .then((_) {});

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> requestPermission() async {
    await _init();
    final android = _android;
    if (android != null) {
      // Null below Android 13, where no permission is asked: then whether
      // the user turned notifications off for the app decides.
      final granted = await android.requestNotificationsPermission();
      return granted ?? await android.areNotificationsEnabled() ?? true;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  @override
  Future<void> replace(List<Reminder> reminders, {required String channelName}) async {
    await _init();
    await _plugin.cancelAll();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channel,
        channelName,
        icon: _icon,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    for (final (i, r) in reminders.indexed) {
      // The local wall-clock time, converted to an instant now: the phone's
      // own time zone rules (daylight saving included) place it.
      await _plugin.zonedSchedule(
        id: i,
        scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
        notificationDetails: details,
        // Within minutes is fine for a reminder, and inexact alarms need no
        // special permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
      );
    }
  }
}
