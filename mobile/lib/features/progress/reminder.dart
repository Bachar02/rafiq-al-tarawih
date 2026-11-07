import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/khatm.dart' show dateOnly;
import '../../data/reading_stats.dart';
import '../../l10n/l10n.dart';
import '../../services/reminders.dart';

/// The days ahead that get a reminder: at most this many, so someone away
/// from the app for a week is not nagged.
const reminderDays = 7;

/// When the next reminders fire: at [minutes] after midnight on each of the
/// next [reminderDays] days, from today if today is not read yet and the
/// time is still ahead, else from tomorrow.
List<DateTime> reminderTimes({required DateTime now, required int minutes, required bool readToday}) {
  final today = dateOnly(now);
  DateTime at(DateTime day) => DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
  final first = !readToday && at(today).isAfter(now) ? today : nextDay(today);
  return [for (var i = 0; i < reminderDays; i++) at(DateTime(first.year, first.month, first.day + i))];
}

String formatMinutes(BuildContext context, int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

/// Keeps the phone's scheduled reminders in step with the app. Each fires
/// only if nothing changed since it was scheduled, so its text (the day's
/// target, where to continue) is computed now: any reading reschedules them,
/// as does showing or hiding the app.
class ReminderSync {
  ReminderSync(this._ref);

  final Ref _ref;
  List<Reminder>? _scheduled;

  /// The reminders that should be scheduled now.
  List<Reminder> plan() {
    final settings = _ref.read(settingsProvider);
    if (!settings.reminderOn) return const [];
    final now = _ref.read(clockProvider)();
    final stats = ReadingStats(
      _ref.read(readingProgressProvider),
      _ref.read(readingSessionProvider).pending,
      now,
    );
    final l = lookupAppLocalizations(_ref.read(appLocaleProvider));
    final quran = _ref.read(quranProvider);
    final names = _ref.read(surahNamesProvider);
    final khatm = _ref.read(khatmProvider).active;
    // A khatm continues at its first unread page; otherwise the reader's place.
    final page = khatm?.nextPage ?? quran.pageOf(_ref.read(readingPositionProvider));
    final surah = names.of(quran.verse(quran.pages.start(page)).surah);
    return [
      for (final at in reminderTimes(now: now, minutes: settings.reminderMinutes, readToday: stats.readToday))
        Reminder(
          at: at,
          title: l.reminderTitle,
          body: switch (khatm?.todayTarget(dateOnly(at)) ?? settings.dailyGoalPages) {
            > 0 && final target => l.reminderBodyTarget(l.pagesCount(target), surah, page),
            _ => l.reminderBody(surah, page),
          },
        ),
    ];
  }

  /// Schedules [plan] if it changed. Never throws: a reminder that cannot be
  /// scheduled must not break reading.
  Future<void> sync({bool force = false}) async {
    final next = plan();
    // Off since the app started and nothing scheduled by this run: leave the
    // notification system alone (turning off cancels explicitly).
    if (!force && next.isEmpty && _scheduled == null) return;
    if (!force && _scheduled != null && _sameList(_scheduled!, next)) return;
    try {
      final l = lookupAppLocalizations(_ref.read(appLocaleProvider));
      await _ref.read(remindersProvider).replace(next, channelName: l.reminderChannel);
      _scheduled = next;
    } catch (e, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'reminders'));
    }
  }

  static bool _sameList(List<Reminder> a, List<Reminder> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Turn the reminder on (at [minutes], else the saved time), after asking
/// for permission to notify. False, with a message, if notifications are off.
Future<bool> turnOnReminder(BuildContext context, WidgetRef ref, {int? minutes}) async {
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
  await ref.read(settingsProvider.notifier).update(
        (s) => s.copyWith(reminderOn: true, reminderMinutes: minutes ?? s.reminderMinutes, reminderOffered: true),
      );
  await ref.read(reminderSyncProvider).sync(force: true);
  if (context.mounted) {
    final time = formatMinutes(context, ref.read(settingsProvider).reminderMinutes);
    messenger.showSnackBar(SnackBar(content: Text(l.reminderSet(time))));
  }
  return true;
}

Future<void> turnOffReminder(WidgetRef ref) async {
  await ref.read(settingsProvider.notifier).update((s) => s.copyWith(reminderOn: false));
  await ref.read(reminderSyncProvider).sync(force: true);
}

/// Pick the reminder's time (the system time picker, in the interface
/// language and the phone's 12/24-hour setting). Null if cancelled.
Future<int?> pickReminderTime(BuildContext context, int current) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
  );
  return picked == null ? null : picked.hour * 60 + picked.minute;
}

Future<void> chooseReminderTime(BuildContext context, WidgetRef ref) async {
  final minutes = await pickReminderTime(context, ref.read(settingsProvider).reminderMinutes);
  if (minutes == null) return;
  await ref.read(settingsProvider.notifier).update((s) => s.copyWith(reminderMinutes: minutes));
  await ref.read(reminderSyncProvider).sync();
}

/// After the first counted reading, offer the reminder once. Never again,
/// whatever the answer.
Future<void> maybeOfferReminder(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider);
  if (settings.reminderOn || settings.reminderOffered) return;
  await ref.read(settingsProvider.notifier).update((s) => s.copyWith(reminderOffered: true));
  if (!context.mounted) return;
  final l = context.l10n;
  final time = formatMinutes(context, settings.reminderMinutes);
  final choice = await showRubricSheet<_Offer>(
    context,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: l.reminderOfferTitle, explanation: l.reminderOfferBody),
          const SizedBox(height: RubricSpace.s4),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _Offer.yes),
            icon: const Icon(Icons.notifications_outlined, size: 20),
            label: Text(l.reminderOfferAt(time)),
          ),
          const SizedBox(height: RubricSpace.s2),
          OutlinedButton(onPressed: () => Navigator.pop(context, _Offer.otherTime), child: Text(l.reminderOtherTime)),
          const SizedBox(height: RubricSpace.s2),
          TextButton(onPressed: () => Navigator.pop(context, _Offer.no), child: Text(l.notNow)),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case _Offer.yes:
      await turnOnReminder(context, ref);
    case _Offer.otherTime:
      final minutes = await pickReminderTime(context, settings.reminderMinutes);
      if (minutes != null && context.mounted) await turnOnReminder(context, ref, minutes: minutes);
    case _Offer.no || null:
      break;
  }
}

enum _Offer { yes, otherTime, no }
