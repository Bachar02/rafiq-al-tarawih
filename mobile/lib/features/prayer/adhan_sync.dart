import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/prayer/prayer_times.dart';
import '../../data/prayer_settings.dart';
import '../../l10n/l10n.dart';
import '../../services/reminders.dart';
import 'prayer_controller.dart';

/// The adhans are scheduled this far ahead, so they are called with the app
/// closed; each time the app is shown or hidden the month moves on. On the
/// last day, a notification asks the user to open Rafiq once.
const adhanDays = 30;

/// Taraweeh mode keeps the adhan silent this long: the microphone is
/// listening to the imam.
const adhanQuietDuringTaraweeh = Duration(hours: 3);

/// The last day's "open Rafiq" notice comes this long after its Isha.
const adhanRenewAfter = Duration(minutes: 30);

/// The renewal notice's place among a day's notifications (after the six
/// times of the day).
const _renewIndex = 7;

/// Keeps the phone's scheduled adhans in step with the prayer settings, the
/// interface language, what Android allows, and Taraweeh mode.
class AdhanSync {
  AdhanSync(this._ref);

  final Ref _ref;
  List<Reminder>? _scheduled;
  DateTime? _quietUntil;

  /// One scheduling at a time, in the order asked.
  Future<void> _last = Future.value();

  /// The adhans that should be scheduled now. [exact]: Android lets them
  /// come on the minute; if not, each is a silent notification, because a
  /// call to prayer an hour late is worse than none.
  List<Reminder> plan({required bool exact}) {
    final settings = _ref.read(prayerSettingsProvider);
    final place = settings.place;
    if (!settings.adhanOn || place == null) return const [];
    final locale = _ref.read(appLocaleProvider);
    final l = lookupAppLocalizations(locale);
    final now = _ref.read(clockProvider)();
    final wallClock = _ref.read(wallClockProvider);
    final quietUntil = _quietUntil;
    final silent = ReminderTone.silent(channelName: l.adhanChannelSilent);

    ReminderTone tone(AdhanAlert alert, DateTime at) {
      if (!exact || (quietUntil != null && !at.isAfter(quietUntil))) return silent;
      return switch (alert) {
        AdhanAlert.sound => ReminderTone.sound(
            settings.sound.resource,
            channelName: settings.sound == AdhanSound.full ? l.adhanChannelFull : l.adhanChannelTakbir,
          ),
        AdhanAlert.vibrate => ReminderTone.vibrate(channelName: l.adhanChannelVibrate),
        AdhanAlert.silent || AdhanAlert.off => silent,
      };
    }

    final body = l.adhanNotificationBody(place.name(locale.languageCode));
    final reminders = <Reminder>[];
    for (var d = 0; d < adhanDays; d++) {
      final date = DateTime(now.year, now.month, now.day + d);
      final times = settings.timesOn(date);
      if (times == null) continue;
      for (final prayer in Prayer.called) {
        final alert = settings.alertOf(prayer);
        if (alert == AdhanAlert.off) continue;
        final at = wallClock(times.at(prayer));
        if (!at.isAfter(now)) continue;
        reminders.add(Reminder(
          at: at,
          title: l.adhanNotificationTitle(prayerName(l, prayer), formatClock(at, locale.languageCode)),
          body: body,
          tone: tone(alert, at),
          slot: adhanSlot(date.year, date.month, date.day, prayer.index),
        ));
      }
      // Nobody opened Rafiq for a month: after the last day's Isha, say
      // that the adhan stops here unless they do.
      if (d == adhanDays - 1 && reminders.isNotEmpty) {
        reminders.add(Reminder(
          at: wallClock(times.at(Prayer.isha)).add(adhanRenewAfter),
          title: l.adhanRenewTitle,
          body: l.adhanRenewBody,
          tone: silent,
          slot: adhanSlot(date.year, date.month, date.day, _renewIndex),
        ));
      }
    }
    return reminders;
  }

  /// Taraweeh mode began (or ended): the adhan stays silent for the next
  /// few hours (or is called as usual again).
  Future<void> taraweeh({required bool on}) {
    _quietUntil = on ? _ref.read(clockProvider)().add(adhanQuietDuringTaraweeh) : null;
    return sync();
  }

  /// Schedules [plan] if it changed ([force]: whatever this run scheduled
  /// before, as after a backup is restored). Never throws: an adhan that
  /// cannot be scheduled must not break anything else.
  Future<void> sync({bool force = false}) => _last = _last.then((_) => _sync(force));

  Future<void> _sync(bool force) async {
    try {
      final settings = _ref.read(prayerSettingsProvider);
      final on = settings.adhanOn && settings.place != null;
      // Off since the app started: leave the notification system alone
      // (turning off cancels through here, once something was scheduled).
      if (!force && !on && _scheduled == null) return;
      final reminders = _ref.read(remindersProvider);
      final exact = !on || await reminders.canScheduleExact();
      final next = plan(exact: exact);
      if (!force && _scheduled != null && sameReminders(_scheduled!, next)) return;
      final l = lookupAppLocalizations(_ref.read(appLocaleProvider));
      await reminders.replace(next, channelName: l.adhan, kind: ReminderKind.adhan);
      _scheduled = next;
    } catch (e, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'adhan'));
    }
  }
}

/// What stands between the adhan and the user, as far as Android tells.
typedef AdhanStatus = ({bool allowed, bool exact});

/// Turn the adhan on: ask for permission to notify, then (Android 12 and
/// later) for permission to set alarms, without which it cannot come on the
/// minute. False, with a message, if notifications are off or the setting
/// could not be saved.
Future<bool> turnOnAdhan(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final reminders = ref.read(remindersProvider);
  bool allowed;
  try {
    allowed = await reminders.requestPermission();
  } catch (_) {
    allowed = false;
  }
  if (!allowed) {
    messenger.showSnackBar(SnackBar(content: Text(l.reminderBlocked)));
    return false;
  }
  var exact = true;
  try {
    exact = await reminders.canScheduleExact();
  } catch (_) {
    // Unknown: the screen's notice will say so if it is not.
  }
  if (!exact && context.mounted) {
    final go = await _explainAlarms(context);
    if (go == true) {
      try {
        await reminders.requestExact();
      } catch (_) {
        // The setting could not be opened: the notice offers it again.
      }
    }
  }
  final saved = await ref.read(prayerSettingsProvider.notifier).update((s) => s.withAdhan(on: true));
  ref.invalidate(adhanStatusProvider);
  messenger.showSnackBar(SnackBar(content: Text(saved ? l.adhanSet : l.prayerNotSaved)));
  return saved;
}

Future<void> turnOffAdhan(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final saved = await ref.read(prayerSettingsProvider.notifier).update((s) => s.withAdhan(on: false));
  if (!saved) messenger.showSnackBar(SnackBar(content: Text(l.prayerNotSaved)));
}

/// Open Android's "Alarms & reminders" setting, then schedule again with
/// whatever the user allowed.
Future<void> allowAdhanAlarms(WidgetRef ref) async {
  try {
    await ref.read(remindersProvider).requestExact();
  } catch (_) {
    // No such setting on this phone.
  }
  ref.invalidate(adhanStatusProvider);
  await ref.read(adhanSyncProvider).sync();
}

/// Call the adhan now, as it will be at prayer time: the chosen recording,
/// on the channel (and at the volume) the real one uses.
Future<void> testAdhan(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final sound = ref.read(prayerSettingsProvider).sound;
  try {
    await ref.read(remindersProvider).show(Reminder(
          at: ref.read(clockProvider)(),
          title: l.adhanTestTitle,
          body: l.adhanTestBody,
          tone: ReminderTone.sound(
            sound.resource,
            channelName: sound == AdhanSound.full ? l.adhanChannelFull : l.adhanChannelTakbir,
          ),
        ));
  } catch (e, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'adhan'));
  }
}

/// Why Android's next screen is coming. True: go on to it.
Future<bool?> _explainAlarms(BuildContext context) {
  final l = context.l10n;
  return showRubricSheet<bool>(
    context,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: l.adhan, explanation: l.adhanExactAsk),
          const SizedBox(height: RubricSpace.s4),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.continueAction)),
          const SizedBox(height: RubricSpace.s2),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.notNow)),
        ],
      ),
    ),
  );
}
