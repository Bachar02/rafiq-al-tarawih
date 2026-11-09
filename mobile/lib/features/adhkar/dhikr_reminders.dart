import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/settings_group.dart';
import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../../services/reminders.dart';
import '../progress/reminder.dart' show formatMinutes;

/// Dhikr reminders come in the day only: the first at [dhikrFromHour], the
/// last at [dhikrToHour], none in the night.
const dhikrFromHour = 8;
const dhikrToHour = 22;

/// Scheduled this far ahead; each time the app is shown or hidden the window
/// moves on. Someone who stops opening Rafiq stops getting them after this.
const dhikrDays = 14;

/// Taraweeh mode keeps them away this long: a dhikr must not cover the
/// imam's ayah.
const dhikrQuietDuringTaraweeh = Duration(hours: 3);

/// When the next dhikr reminders fire: every [everyHours] from
/// [dhikrFromHour] to [dhikrToHour] on each of the next [dhikrDays] days,
/// after [now] (and after [quietUntil]).
List<DateTime> dhikrTimes({required DateTime now, required int everyHours, DateTime? quietUntil}) {
  final after = quietUntil != null && quietUntil.isAfter(now) ? quietUntil : now;
  return [
    for (var d = 0; d < dhikrDays; d++)
      for (var h = dhikrFromHour; h <= dhikrToHour; h += everyHours)
        if (DateTime(now.year, now.month, now.day + d, h) case final at when at.isAfter(after)) at,
  ];
}

/// Which of [count] adhkar to show at [at]: random-looking, but the same
/// for the same hour, so scheduling again changes nothing.
int dhikrPick(DateTime at, int count) {
  var x = at.year * 1000000 + at.month * 10000 + at.day * 100 + at.hour;
  for (var i = 0; i < 2; i++) {
    x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0x7fffffff;
  }
  return (x ^ (x >> 16)) % count;
}

/// Keeps the phone's scheduled dhikr reminders in step with the settings,
/// the interface language and Taraweeh mode.
class DhikrSync {
  DhikrSync(this._ref);

  final Ref _ref;
  List<Reminder>? _scheduled;
  DateTime? _quietUntil;

  /// The reminders that should be scheduled now.
  List<Reminder> plan() {
    final settings = _ref.read(settingsProvider);
    if (!settings.dhikrRemindersOn) return const [];
    final pool = _ref.read(adhkarProvider).forNotifications;
    if (pool.isEmpty) return const [];
    final locale = _ref.read(appLocaleProvider);
    final l = lookupAppLocalizations(locale);
    final now = _ref.read(clockProvider)();
    final reminders = <Reminder>[];
    var previous = -1;
    for (final at in dhikrTimes(now: now, everyHours: settings.dhikrEveryHours, quietUntil: _quietUntil)) {
      var i = dhikrPick(at, pool.length);
      if (i == previous) i = (i + 1) % pool.length; // never the same one twice in a row
      previous = i;
      final dhikr = pool[i];
      // The words, then (except in Arabic) their meaning.
      final meaning = dhikr.meaning(locale.languageCode);
      reminders.add(Reminder(
        at: at,
        title: l.dhikrNotificationTitle,
        body: meaning == null ? dhikr.arabic! : '${dhikr.arabic}\n$meaning',
      ));
    }
    return reminders;
  }

  /// Taraweeh mode began (or ended): no dhikr for the next few hours (or
  /// back to the usual ones).
  Future<void> taraweeh({required bool on}) {
    _quietUntil = on ? _ref.read(clockProvider)().add(dhikrQuietDuringTaraweeh) : null;
    return sync();
  }

  /// Schedules [plan] if it changed. Never throws: a notification that
  /// cannot be scheduled must not break anything else.
  Future<void> sync({bool force = false}) async {
    final next = plan();
    // Off since the app started: leave the notification system alone
    // (turning off cancels explicitly).
    if (!force && next.isEmpty && _scheduled == null) return;
    if (!force && _scheduled != null && sameReminders(_scheduled!, next)) return;
    try {
      final l = lookupAppLocalizations(_ref.read(appLocaleProvider));
      await _ref.read(remindersProvider).replace(next, channelName: l.dhikrReminders, kind: ReminderKind.dhikr);
      _scheduled = next;
    } catch (e, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'dhikr reminders'));
    }
  }
}

/// Turn dhikr reminders on, after asking for permission to notify. False,
/// with a message, if notifications are off.
Future<bool> turnOnDhikrReminders(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  bool allowed;
  try {
    allowed = await ref.read(remindersProvider).requestPermission();
  } catch (_) {
    allowed = false;
  }
  if (!allowed) {
    messenger.showSnackBar(SnackBar(content: Text(l.reminderBlocked)));
    return false;
  }
  await ref.read(settingsProvider.notifier).update((s) => s.copyWith(dhikrRemindersOn: true));
  await ref.read(dhikrSyncProvider).sync(force: true);
  messenger.showSnackBar(SnackBar(content: Text(l.dhikrRemindersSet)));
  return true;
}

Future<void> turnOffDhikrReminders(WidgetRef ref) async {
  await ref.read(settingsProvider.notifier).update((s) => s.copyWith(dhikrRemindersOn: false));
  await ref.read(dhikrSyncProvider).sync(force: true);
}

String _hour(BuildContext context, int hour) => formatMinutes(context, hour * 60);

/// Dhikr reminders: on or off, and how often. On the Adhkar screen and in
/// Settings.
class DhikrReminderSettings extends ConsumerWidget {
  const DhikrReminderSettings({super.key});

  Future<void> _chooseInterval(BuildContext context, WidgetRef ref, int current) async {
    final l = context.l10n;
    final hours = await showRubricSheet<int>(
      context,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(
              title: l.dhikrHowOften,
              explanation: l.dhikrHowOftenExplanation(_hour(context, dhikrFromHour), _hour(context, dhikrToHour)),
            ),
            const SizedBox(height: RubricSpace.s4),
            RubricGroup(
              children: [
                for (final option in AppSettings.dhikrIntervals)
                  RubricRow(
                    label: l.dhikrEvery(option),
                    selected: option == current,
                    trailing: option == current ? Icon(Icons.check, color: context.colors.ink, size: 20) : null,
                    onTap: () => Navigator.pop(context, option),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (hours == null || hours == current) return;
    await ref.read(settingsProvider.notifier).update((s) => s.copyWith(dhikrEveryHours: hours));
    await ref.read(dhikrSyncProvider).sync();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final on = ref.watch(settingsProvider.select((s) => s.dhikrRemindersOn));
    final every = ref.watch(settingsProvider.select((s) => s.dhikrEveryHours));
    Future<void> toggle(bool value) => value ? turnOnDhikrReminders(context, ref) : turnOffDhikrReminders(ref);
    return RubricGroup(
      label: l.dhikrReminders,
      children: [
        RubricRow(
          label: l.dhikrReminders,
          detail: on
              ? l.dhikrRemindersDetail(l.dhikrEvery(every), _hour(context, dhikrFromHour), _hour(context, dhikrToHour))
              : l.dhikrRemindersOff,
          onTap: () => toggle(!on),
          trailing: Switch(value: on, onChanged: toggle),
        ),
        if (on)
          RubricRow(
            label: l.dhikrHowOften,
            value: l.dhikrEvery(every),
            onTap: () => _chooseInterval(context, ref, every),
          ),
      ],
    );
  }
}
