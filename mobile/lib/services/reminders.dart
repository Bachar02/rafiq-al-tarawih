/// Local notifications, scheduled on the phone: the daily reading reminder,
/// the dhikr that pops up now and then, and the adhan at each prayer time.
/// Nothing leaves the phone.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// One notification: when (local time) and what it says.
class Reminder {
  const Reminder({
    required this.at,
    required this.title,
    required this.body,
    this.expanded,
    this.tone,
    this.slot = 0,
  });

  final DateTime at;
  final String title;

  /// One line when collapsed.
  final String body;

  /// The whole text when expanded, if more than [body].
  final String? expanded;

  /// How it makes itself known ([ReminderKind.adhan] only: the other kinds
  /// each have one fixed way).
  final ReminderTone? tone;

  /// Its place among its kind's ids ([ReminderKind.adhan] only): the same
  /// prayer of the same day keeps its slot from one scheduling to the next.
  final int slot;

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.at == at &&
      other.title == title &&
      other.body == body &&
      other.expanded == expanded &&
      other.tone == tone &&
      other.slot == slot;

  @override
  int get hashCode => Object.hash(at, title, body, expanded, tone, slot);
}

/// How an adhan makes itself known: a recording, a vibration, or neither.
/// Android fixes sound and vibration per notification channel, so each tone
/// is a channel of its own, which the user can also tune in the phone's
/// settings under [channelName].
@immutable
class ReminderTone {
  /// The adhan: [sound] is a raw resource of the Android app, without its
  /// extension. It also vibrates, which is all that is left of it when the
  /// phone is set to vibrate.
  const ReminderTone.sound(String this.sound, {required this.channelName}) : vibrate = true;

  /// A vibration, no sound.
  const ReminderTone.vibrate({required this.channelName})
      : sound = null,
        vibrate = true;

  /// Neither: a notification to be seen.
  const ReminderTone.silent({required this.channelName})
      : sound = null,
        vibrate = false;

  final String? sound;
  final bool vibrate;

  /// The channel's name in the phone's notification settings, in the
  /// interface language.
  final String channelName;

  /// One channel per recording, one for the vibration, one for silence.
  String get channelId => sound ?? (vibrate ? 'adhan_vibrate' : 'adhan_silent');

  bool get isSilent => sound == null && !vibrate;

  @override
  bool operator ==(Object other) =>
      other is ReminderTone && other.sound == sound && other.vibrate == vibrate && other.channelName == channelName;

  @override
  int get hashCode => Object.hash(sound, vibrate, channelName);
}

bool sameReminders(List<Reminder> a, List<Reminder> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The kinds of notification, each with its own channels (the user can
/// silence one in Android's settings and keep the others) and its own ids,
/// so replacing one never touches the others.
enum ReminderKind {
  /// The daily reading reminder: an ordinary notification.
  reading,

  /// A dhikr: pops up at the top of the screen, silent, and goes by itself.
  dhikr,

  /// The adhan: at the prayer's minute where Android allows it, each with
  /// its own [Reminder.tone].
  adhan,
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

/// What an adhan notification opens when tapped. Its payload starts with
/// this; the rest tells one scheduling from another (see [isAdhanPayload]).
const adhanPayload = 'prayer';

bool isAdhanPayload(String payload) => payload == adhanPayload || payload.startsWith('$adhanPayload|');

/// How long an adhan stays in the shade: by then the prayer is under way.
const adhanShownFor = Duration(minutes: 30);

/// Adhan ids: [adhanIdBase] + the reminder's [Reminder.slot], below
/// [adhanIdBase] + [adhanIdCycle]. The last id is the test's.
const adhanIdBase = 2000;
const adhanIdCycle = 500;
const adhanTestId = adhanIdBase + adhanIdCycle - 1;

/// The slots of a day's adhans: [adhanSlotsPerDay] for each of
/// [adhanSlotDays] days, after which the days come round again.
const adhanSlotsPerDay = 8;
const adhanSlotDays = 60;

/// The slot of the [index]th notification (0..7) of the calendar day
/// [year]-[month]-[day].
int adhanSlot(int year, int month, int day, int index) {
  assert(index >= 0 && index < adhanSlotsPerDay);
  final days = DateTime.utc(year, month, day).difference(DateTime.utc(2000)).inDays;
  return (days % adhanSlotDays) * adhanSlotsPerDay + index;
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

  /// Whether notifications are allowed for the app. Never asks.
  Future<bool> allowed();

  /// Whether a notification can be scheduled for an exact minute. Android 12
  /// and later keep that for apps the user allows to set alarms ("Alarms &
  /// reminders"); without it a notification may come up to an hour late.
  Future<bool> canScheduleExact();

  /// Opens the phone's "Alarms & reminders" setting for the app, and says
  /// whether exact scheduling is allowed once the user comes back.
  Future<bool> requestExact();

  /// Shows [reminder] now, whatever its time: the adhan's test.
  Future<void> show(Reminder reminder);
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

  /// The first adhans of a new process are scheduled this many at once; the
  /// rest follow one at a time, [_breath] apart (see [_replaceAdhan]).
  static const _atOnce = 12;
  static const _breath = Duration(milliseconds: 40);

  /// Nothing scheduled by this process yet: its first adhans are all set
  /// again, whatever the plugin's list says.
  bool _adhanUnchecked = true;

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
      case ReminderKind.adhan:
        await _replaceAdhan(reminders);
    }
  }

  @override
  Future<bool> allowed() async {
    await _init();
    return await _android?.areNotificationsEnabled() ?? true;
  }

  @override
  Future<bool> canScheduleExact() async {
    await _init();
    // Not Android: notifications are always on time.
    return await _android?.canScheduleExactNotifications() ?? true;
  }

  @override
  Future<bool> requestExact() async {
    await _init();
    final android = _android;
    if (android == null) return true;
    await android.requestExactAlarmsPermission();
    return await android.canScheduleExactNotifications() ?? true;
  }

  @override
  Future<void> show(Reminder reminder) async {
    await _init();
    await _plugin.show(
      id: adhanTestId,
      title: reminder.title,
      body: reminder.body,
      notificationDetails: _adhanDetails(reminder),
      payload: adhanPayload,
    );
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

  /// The adhans: a month of them, each at its prayer's minute if Android
  /// allows exact alarms, else whenever Android delivers it.
  ///
  /// As for the dhikr, only what changed is cancelled or scheduled. But the
  /// plugin's list of what is pending is its own record, not Android's: a
  /// phone that force-stops the app (or a maker's battery saver that does
  /// the same when the app is swiped away) drops every alarm and leaves the
  /// record as it was. So the first time a process schedules, every adhan
  /// is set again: the next few at once, the rest spaced out so that
  /// opening the app stays smooth.
  Future<void> _replaceAdhan(List<Reminder> reminders) async {
    final exact = await canScheduleExact();
    bool ours(int id) => id >= adhanIdBase && id < adhanIdBase + adhanIdCycle && id != adhanTestId;
    final pending = {
      for (final p in await _plugin.pendingNotificationRequests())
        if (ours(p.id)) p.id: p,
    };
    final wanted = {for (final r in reminders) adhanIdBase + r.slot: r};
    // The payload tells the channel and the mode: a change of tone, or of
    // the permission, is a change even when the words are the same.
    String payload(Reminder r) => '$adhanPayload|${r.tone?.channelId}|${exact ? 'exact' : 'inexact'}';
    bool same(PendingNotificationRequest p, Reminder r) =>
        p.title == r.title && p.body == r.body && p.payload == payload(r);
    final unchecked = _adhanUnchecked;
    _adhanUnchecked = false;
    for (final MapEntry(key: id, value: p) in pending.entries) {
      final r = wanted[id];
      if (r == null || !same(p, r)) await _plugin.cancel(id: id);
    }
    var set = 0;
    for (final MapEntry(key: id, value: r) in wanted.entries) {
      final p = pending[id];
      if (!unchecked && p != null && same(p, r)) continue;
      if (unchecked && set >= _atOnce) await Future<void>.delayed(_breath);
      await _schedule(
        id,
        r,
        _adhanDetails(r),
        payload: payload(r),
        mode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      );
      set++;
    }
  }

  static const _adhanGroup = 'adhan';

  /// A long buzz, a pause, and again: felt in a pocket, unlike a message.
  static final _vibration = Int64List.fromList([0, 600, 300, 600, 300, 900]);

  NotificationDetails _adhanDetails(Reminder r) {
    final tone = r.tone!;
    final sound = tone.sound;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        tone.channelId,
        tone.channelName,
        icon: _icon,
        // Heard or felt: at the top of the screen. Silent: in the shade.
        importance: tone.isSilent ? Importance.defaultImportance : Importance.high,
        priority: tone.isSilent ? Priority.defaultPriority : Priority.high,
        playSound: sound != null,
        sound: sound == null ? null : RawResourceAndroidNotificationSound(sound),
        enableVibration: tone.vibrate,
        vibrationPattern: tone.vibrate ? _vibration : null,
        timeoutAfter: adhanShownFor.inMilliseconds,
        // A reminder: Android 16's notification cooldown lets reminders
        // through at full volume.
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        // A group of the app's own. Android 16 gathers an app's ungrouped
        // notifications into one group, and silences one that arrives while
        // another is still in the shade (the reading reminder, an earlier
        // adhan): it marks the newcomer silent before it sounds. One that
        // names its group is left alone until it has been heard.
        groupKey: _adhanGroup,
      ),
      iOS: DarwinNotificationDetails(presentSound: sound != null),
    );
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

  Future<void> _schedule(
    int id,
    Reminder r,
    NotificationDetails details, {
    String? payload,
    // Within minutes is fine for a reminder, and inexact alarms need no
    // special permission. Only the adhan asks for the minute.
    AndroidScheduleMode mode = AndroidScheduleMode.inexactAllowWhileIdle,
  }) =>
      _plugin.zonedSchedule(
        id: id,
        // The local wall-clock time, converted to an instant now: the
        // phone's own time zone rules (daylight saving included) place it.
        scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
        notificationDetails: details,
        androidScheduleMode: mode,
        title: r.title,
        body: r.body,
        payload: payload,
      );
}
