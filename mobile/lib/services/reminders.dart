/// Local notifications, scheduled on the phone: the daily reading reminder,
/// the dhikr that comes now and then, and the adhan at each prayer time.
/// Nothing leaves the phone.
library;

import 'dart:io' show Platform;
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter/services.dart' show MethodChannel;
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

/// The kinds of notification [Reminders.replace] schedules, each with its
/// own channels (the user can silence one in Android's settings and keep the
/// others) and its own ids, so replacing one never touches the others. The
/// dhikr is apart: a rule, not a list ([Reminders.scheduleDhikr]).
enum ReminderKind {
  /// The daily reading reminder: a notification at the top of the screen.
  reading,

  /// The adhan: at the prayer's minute where Android allows it, each with
  /// its own [Reminder.tone].
  adhan,
}

/// What a reading reminder opens when tapped: the reader, where the user
/// left off.
const readingPayload = 'reading';

/// What a dhikr notification opens when tapped.
const dhikrPayload = 'adhkar';

/// One dhikr as the reminders show it: the Arabic words, how to say them in
/// Latin letters ([said]), and what they mean. [said] and [meaning] are for
/// an interface that is not Arabic.
@immutable
class DhikrText {
  const DhikrText({required this.id, required this.arabic, this.said, this.meaning});

  /// The dhikr's id: the same dhikr in another language keeps it.
  final String id;
  final String arabic;
  final String? said;
  final String? meaning;

  /// Everything, one per line: the expanded notification.
  String get expanded => [arabic, if (said != null) said!, if (meaning != null) meaning!].join('\n');

  Map<String, Object?> toMap() => {'id': id, 'arabic': arabic, 'said': said, 'meaning': meaning};

  @override
  bool operator ==(Object other) =>
      other is DhikrText && other.id == id && other.arabic == arabic && other.said == said && other.meaning == meaning;

  @override
  int get hashCode => Object.hash(id, arabic, said, meaning);
}

/// The dhikr reminders as a rule the phone follows by itself, for as long
/// as it is on: one on the hour every [everyHours] hours from [fromHour] to
/// [toHour] each day (local time), none at or before [quietUntil], each
/// drawn when it comes from [items] (see [DhikrDeck]). No [items]: off.
///
/// android/.../Dhikr.kt follows the same rule; [times] is it in Dart.
@immutable
class DhikrPlan {
  const DhikrPlan({
    required this.title,
    required this.everyHours,
    required this.fromHour,
    required this.toHour,
    required this.items,
    this.quietUntil,
  });

  /// No reminders.
  static const off = DhikrPlan(title: '', everyHours: 1, fromHour: 0, toHour: 0, items: []);

  /// Above each dhikr: the card's and the notification's title.
  final String title;
  final int everyHours;
  final int fromHour;
  final int toHour;
  final DateTime? quietUntil;
  final List<DhikrText> items;

  bool get isOff => items.isEmpty;

  /// The slots after [now] (and after [quietUntil]) on each of the [days]
  /// days from [now]'s.
  List<DateTime> times({required DateTime now, required int days}) {
    final quiet = quietUntil;
    final after = quiet != null && quiet.isAfter(now) ? quiet : now;
    final step = everyHours < 1 ? 1 : everyHours;
    return [
      for (var d = 0; d < days; d++)
        for (var h = fromHour; h <= toHour; h += step)
          if (DateTime(now.year, now.month, now.day + d, h) case final at when at.isAfter(after)) at,
    ];
  }

  Map<String, Object?> toMap() => {
        'title': title,
        'every': everyHours,
        'from': fromHour,
        'to': toHour,
        'quietUntil': quietUntil?.millisecondsSinceEpoch,
        'items': [for (final i in items) i.toMap()],
      };

  @override
  bool operator ==(Object other) =>
      other is DhikrPlan &&
      other.title == title &&
      other.everyHours == everyHours &&
      other.fromHour == fromHour &&
      other.toHour == toHour &&
      other.quietUntil == quietUntil &&
      listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(title, everyHours, fromHour, toHour, quietUntil, Object.hashAll(items));
}

/// Which dhikr comes next: a shuffled bag. Every one of the adhkar comes
/// once, in a random order, before the bag is shuffled again; the first of
/// a round is never the last of the round before, so the same dhikr never
/// comes twice in a row. (android/.../Dhikr.kt draws the same way.)
class DhikrDeck {
  DhikrDeck([Random? random]) : _random = random ?? Random();

  final Random _random;
  final _bag = <String>[];
  String? _last;

  /// The next of [items] (not empty). Adhkar no longer offered drop out of
  /// the bag; new ones join at the next shuffle.
  DhikrText draw(List<DhikrText> items) {
    assert(items.isNotEmpty);
    final byId = {for (final i in items) i.id: i};
    _bag.removeWhere((id) => !byId.containsKey(id));
    if (_bag.isEmpty) {
      _bag.addAll(byId.keys.toList()..shuffle(_random));
      if (_bag.length > 1 && _bag.first == _last) _bag.add(_bag.removeAt(0));
    }
    final id = _bag.removeAt(0);
    _last = id;
    return byId[id]!;
  }
}

/// Dhikr ids, where the plugin schedules them (not Android): [dhikrIdBase] +
/// the hour's place in a cycle of [dhikrIdCycle] hours (about three weeks),
/// so each hour of the [dhikrDays] scheduled ahead has its own id. On
/// Android these ids only name what flutter_local_notifications scheduled up
/// to 0.8, cancelled once: the app's own code now shows the dhikr.
const dhikrIdBase = 1000;
const dhikrIdCycle = 500;

/// Where the plugin schedules the dhikr (not Android): this many days ahead.
const dhikrDays = 14;

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

  /// From now on, the dhikr reminders follow [plan] ([DhikrPlan.off]: none).
  /// [closeLabel] is what a screen reader says closes a dhikr's card.
  Future<void> scheduleDhikr(DhikrPlan plan, {required String channelName, required String closeLabel});

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

  /// Whether a dhikr can be shown in its card on the screen, over other
  /// apps: Android's "Appear on top" permission. False elsewhere.
  Future<bool> canShowOnScreen();

  /// Opens the phone's "Appear on top" setting for the app, and says whether
  /// it is allowed once the user comes back.
  Future<bool> requestShowOnScreen();

  /// Shows a dhikr now, drawn from [plan]'s adhkar the way the scheduled
  /// ones are.
  Future<void> showDhikr(DhikrPlan plan, {required String channelName, required String closeLabel});
}

/// [Reminders] through flutter_local_notifications.
class LocalReminders implements Reminders {
  LocalReminders([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;
  void Function(String payload)? _onOpen;
  bool _launchHandled = false;

  /// A channel of high importance, so the reminder shows at the top of the
  /// screen. Android fixes a channel's importance once created, so the
  /// first one (`daily_reading`, of default importance: the shade only) is
  /// deleted and this one takes its place.
  static const _readingChannel = 'reading_reminder';
  static const _oldReadingChannel = 'daily_reading';
  static const _readingGroup = 'reading';
  static const _dhikrChannel = 'adhkar';

  /// The app's own Android code: the dhikr's alarms, its card on the screen,
  /// and the "Appear on top" permission (android/.../Dhikr.kt).
  static const _native = MethodChannel('app.rafiq.rafiq/dhikr');

  /// The dhikr is the app's own on Android; elsewhere the plugin notifies.
  static bool get _nativeDhikr => Platform.isAndroid;

  /// What 0.8 and earlier left: the plugin's dhikr notifications and the
  /// default-importance reading channel, cleared by the first scheduling of
  /// each process.
  bool _oldCleared = false;

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
    if (_nativeDhikr) {
      // A dhikr's notification (no "Appear on top") opens the app itself.
      _native.setMethodCallHandler((call) async {
        if (call.method == 'open') _onOpen?.call(dhikrPayload);
      });
    }
    if (_launchHandled) return;
    _launchHandled = true;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) && payload != null) {
      handler(payload);
    } else if (_nativeDhikr && await _native.invokeMethod<String>('takeLaunchOpen') != null) {
      handler(dhikrPayload);
    }
  }

  @override
  Future<void> replace(
    List<Reminder> reminders, {
    required String channelName,
    ReminderKind kind = ReminderKind.reading,
  }) async {
    await _init();
    await _clearOld();
    switch (kind) {
      case ReminderKind.reading:
        await _replaceReading(reminders, channelName);
      case ReminderKind.adhan:
        await _replaceAdhan(reminders);
    }
  }

  @override
  Future<void> scheduleDhikr(DhikrPlan plan, {required String channelName, required String closeLabel}) async {
    await _init();
    await _clearOld();
    if (_nativeDhikr) {
      await _native.invokeMethod<void>('schedule', {
        'plan': plan.isOff ? null : plan.toMap(),
        'channelName': channelName,
        'closeLabel': closeLabel,
      });
    } else {
      await _replaceDhikr(plan, channelName);
    }
  }

  /// Not Android: which dhikr each notification brings.
  final _deck = DhikrDeck();

  Future<void> _clearOld() async {
    if (_oldCleared || !Platform.isAndroid) return;
    _oldCleared = true;
    await _android?.deleteNotificationChannel(channelId: _oldReadingChannel);
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id >= dhikrIdBase && p.id < dhikrIdBase + dhikrIdCycle) await _plugin.cancel(id: p.id);
    }
  }

  @override
  Future<bool> canShowOnScreen() async =>
      _nativeDhikr && (await _native.invokeMethod<bool>('canShowOnScreen') ?? false);

  @override
  Future<bool> requestShowOnScreen() async =>
      _nativeDhikr && (await _native.invokeMethod<bool>('requestShowOnScreen') ?? false);

  @override
  Future<void> showDhikr(DhikrPlan plan, {required String channelName, required String closeLabel}) async {
    if (plan.isOff) return;
    if (_nativeDhikr) {
      await _native.invokeMethod<void>('show', {
        'plan': plan.toMap(),
        'channelName': channelName,
        'closeLabel': closeLabel,
      });
      return;
    }
    await _init();
    final text = _deck.draw(plan.items);
    await _plugin.show(
      id: dhikrIdBase + dhikrIdCycle - 1,
      title: plan.title,
      body: text.arabic,
      notificationDetails: _dhikrDetails(text, channelName),
      payload: dhikrPayload,
    );
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
        // At the top of the screen, with the phone's notification sound.
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.public,
        // Its own group: Android 16 marks an ungrouped notification silent
        // when another of the app's is already in the shade (see the adhan's).
        groupKey: _readingGroup,
      ),
      iOS: const DarwinNotificationDetails(),
    );
    // On the minute when Android allows it (the adhan asks), else within
    // Android's window (up to an hour).
    final mode =
        await canScheduleExact() ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    for (final (i, r) in reminders.take(_readingIds).indexed) {
      await _schedule(i, r, details, mode: mode, payload: readingPayload);
    }
  }

  /// Not Android: no code of the app's own runs at a dhikr's time, so the
  /// plugin schedules the next [dhikrDays] days of them, each dhikr drawn
  /// now. Moved on whenever the app sends the plan again (daily at most).
  Future<void> _replaceDhikr(DhikrPlan plan, String channelName) async {
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id >= dhikrIdBase && p.id < dhikrIdBase + dhikrIdCycle) await _plugin.cancel(id: p.id);
    }
    if (plan.isOff) return;
    for (final at in plan.times(now: DateTime.now(), days: dhikrDays)) {
      final text = _deck.draw(plan.items);
      await _schedule(
        dhikrNotificationId(at),
        Reminder(at: at, title: plan.title, body: text.arabic, expanded: text.expanded),
        _dhikrDetails(text, channelName),
        payload: dhikrPayload,
      );
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

  /// Not Android: a notification, silent, that waits until it is seen.
  NotificationDetails _dhikrDetails(DhikrText text, String channelName) => NotificationDetails(
        android: AndroidNotificationDetails(
          _dhikrChannel,
          channelName,
          icon: _icon,
          importance: Importance.high,
          priority: Priority.high,
          playSound: false,
          enableVibration: false,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
          // The whole dhikr, how to say it and its meaning when expanded.
          styleInformation: BigTextStyleInformation(text.expanded),
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
