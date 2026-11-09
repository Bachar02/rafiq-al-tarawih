/// Local notifications, scheduled on the phone: the daily reading reminder
/// and the dhikr that pops up now and then. Nothing leaves the phone.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// One notification: when (local time) and what it says.
class Reminder {
  const Reminder({required this.at, required this.title, required this.body, this.expanded});

  final DateTime at;
  final String title;

  /// One line when collapsed.
  final String body;

  /// The whole text when expanded, if more than [body].
  final String? expanded;

  @override
  bool operator ==(Object other) =>
      other is Reminder && other.at == at && other.title == title && other.body == body && other.expanded == expanded;

  @override
  int get hashCode => Object.hash(at, title, body, expanded);
}

bool sameReminders(List<Reminder> a, List<Reminder> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The two kinds of notification, each with its own channel (the user can
/// silence one in Android's settings and keep the other) and its own ids,
/// so replacing one never touches the other.
enum ReminderKind {
  /// The daily reading reminder: an ordinary notification.
  reading,

  /// A dhikr: pops up at the top of the screen, silent, and goes by itself.
  dhikr,
}

/// What a dhikr notification opens when tapped.
const dhikrPayload = 'adhkar';

/// How long a dhikr stays on screen (and in the shade) before it goes.
const dhikrShownFor = Duration(seconds: 8);

/// Dhikr ids: [dhikrIdBase] + the hour's place in a cycle of [dhikrIdCycle]
/// hours (about three weeks), so each hour of the two weeks scheduled ahead
/// has its own id, and the same hour keeps it from one scheduling to the next.
const dhikrIdBase = 1000;
const dhikrIdCycle = 500;

int dhikrNotificationId(DateTime at) {
  final day = DateTime.utc(at.year, at.month, at.day).difference(DateTime.utc(2000)).inDays;
  return dhikrIdBase + (day * 24 + at.hour) % dhikrIdCycle;
}

/// The phone's notifications (tests replace it).
abstract interface class Reminders {
  /// Asks for permission to notify (Android 13+). True if notifications
  /// can be shown.
  Future<bool> requestPermission();

  /// Replaces every scheduled notification of [kind] with [reminders]
  /// (none: cancel them all). [channelName] is the name Android shows in the
  /// app's notification settings, in the interface language.
  Future<void> replace(List<Reminder> reminders, {required String channelName, ReminderKind kind});

  /// Calls [handler] with the payload of a notification the user taps,
  /// including one that launched the app.
  Future<void> onOpen(void Function(String payload) handler);
}

/// [Reminders] through flutter_local_notifications.
class LocalReminders implements Reminders {
  LocalReminders([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;
  void Function(String payload)? _onOpen;
  bool _launchHandled = false;

  static const _readingChannel = 'daily_reading';
  static const _dhikrChannel = 'adhkar';

  /// Reading reminders use ids 0 to this (a week, with room to spare).
  static const _readingIds = 16;

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
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null) _onOpen?.call(payload);
        },
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
  Future<void> onOpen(void Function(String payload) handler) async {
    _onOpen = handler;
    await _init();
    if (_launchHandled) return;
    _launchHandled = true;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) && payload != null) handler(payload);
  }

  @override
  Future<void> replace(
    List<Reminder> reminders, {
    required String channelName,
    ReminderKind kind = ReminderKind.reading,
  }) async {
    await _init();
    switch (kind) {
      case ReminderKind.reading:
        await _replaceReading(reminders, channelName);
      case ReminderKind.dhikr:
        await _replaceDhikr(reminders, channelName);
    }
  }

  Future<void> _replaceReading(List<Reminder> reminders, String channelName) async {
    // Cancelling also clears one already shown: read today, it goes.
    for (var id = 0; id < _readingIds; id++) {
      await _plugin.cancel(id: id);
    }
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _readingChannel,
        channelName,
        icon: _icon,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    for (final (i, r) in reminders.take(_readingIds).indexed) {
      await _schedule(i, r, details);
    }
  }

  /// Two weeks of dhikr is a hundred or so notifications: only what changed
  /// is cancelled or scheduled (each call writes the plugin's whole list).
  Future<void> _replaceDhikr(List<Reminder> reminders, String channelName) async {
    bool ours(int id) => id >= dhikrIdBase && id < dhikrIdBase + dhikrIdCycle;
    final pending = {
      for (final p in await _plugin.pendingNotificationRequests())
        if (ours(p.id)) p.id: p,
    };
    final wanted = {for (final r in reminders) dhikrNotificationId(r.at): r};
    bool same(PendingNotificationRequest p, Reminder r) => p.title == r.title && p.body == r.body;
    for (final MapEntry(key: id, value: p) in pending.entries) {
      final r = wanted[id];
      if (r == null || !same(p, r)) await _plugin.cancel(id: id);
    }
    for (final MapEntry(key: id, value: r) in wanted.entries) {
      final p = pending[id];
      if (p != null && same(p, r)) continue;
      await _schedule(id, r, _dhikrDetails(r, channelName), payload: dhikrPayload);
    }
  }

  /// High importance is what makes Android show it at the top of the screen
  /// (a heads-up notification); no sound and no vibration, so it never
  /// disturbs; it removes itself after [dhikrShownFor].
  NotificationDetails _dhikrDetails(Reminder r, String channelName) => NotificationDetails(
        android: AndroidNotificationDetails(
          _dhikrChannel,
          channelName,
          icon: _icon,
          importance: Importance.high,
          priority: Priority.high,
          playSound: false,
          enableVibration: false,
          timeoutAfter: dhikrShownFor.inMilliseconds,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
          // The whole dhikr and its meaning when expanded.
          styleInformation: BigTextStyleInformation(r.expanded ?? r.body),
        ),
        iOS: const DarwinNotificationDetails(presentSound: false),
      );

  Future<void> _schedule(int id, Reminder r, NotificationDetails details, {String? payload}) => _plugin.zonedSchedule(
        id: id,
        // The local wall-clock time, converted to an instant now: the
        // phone's own time zone rules (daylight saving included) place it.
        scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
        notificationDetails: details,
        // Within minutes is fine, and inexact alarms need no special
        // permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
        payload: payload,
      );
}
