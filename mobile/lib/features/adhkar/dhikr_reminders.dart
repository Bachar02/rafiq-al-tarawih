import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/settings_group.dart';
import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/adhkar.dart' show Dhikr;
import '../../data/khatm.dart' show dateOnly;
import '../../data/settings.dart';
import '../../l10n/l10n.dart';
import '../../services/reminders.dart';
import '../progress/reminder.dart' show formatMinutes;

/// Dhikr reminders come in the day only: the first at [dhikrFromHour], the
/// last at [dhikrToHour], none in the night.
const dhikrFromHour = 8;
const dhikrToHour = 22;

/// Taraweeh mode keeps them away this long: a dhikr must not cover the
/// imam's ayah.
const dhikrQuietDuringTaraweeh = Duration(hours: 3);

/// When the next dhikr reminders come, over the next [days] days: every
/// [everyHours] from [dhikrFromHour] to [dhikrToHour], after [now] (and
/// after [quietUntil]). The phone follows the same rule by itself, with no
/// end ([DhikrPlan]).
List<DateTime> dhikrTimes({
  required DateTime now,
  required int everyHours,
  DateTime? quietUntil,
  int days = dhikrDays,
}) =>
    DhikrPlan(
      title: '',
      everyHours: everyHours,
      fromHour: dhikrFromHour,
      toHour: dhikrToHour,
      quietUntil: quietUntil,
      items: const [],
    ).times(now: now, days: days);

/// Whether a dhikr can come in its card at the top right of the screen
/// ("Appear on top"); asked again after the user visits the setting.
final dhikrOnScreenProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(remindersProvider).canShowOnScreen();
  } catch (_) {
    return false;
  }
});

/// [dhikr] as the reminders show it in [languageCode]: always the Arabic
/// words; outside Arabic, how to say them in Latin letters (in the card and
/// the notification) and their meaning (in the expanded notification).
DhikrText dhikrText(Dhikr dhikr, String languageCode) => DhikrText(
      id: dhikr.id,
      arabic: dhikr.arabic!,
      said: dhikr.transliteration(languageCode),
      meaning: dhikr.meaning(languageCode),
    );

/// Keeps the phone's dhikr reminders in step with the settings, the
/// interface language and Taraweeh mode.
///
/// The phone is given a rule ([DhikrPlan]) and follows it by itself, so a
/// dhikr keeps coming however long Rafiq stays closed. The plan is sent
/// again only when it changes, and once a day (where the plugin schedules
/// the next days, not Android, that moves them on).
class DhikrSync {
  DhikrSync(this._ref);

  final Ref _ref;
  DhikrPlan? _sent;
  DateTime? _sentOn;
  DateTime? _quietUntil;

  /// What the phone should follow now ([DhikrPlan.off] when turned off).
  DhikrPlan plan() {
    final settings = _ref.read(settingsProvider);
    if (!settings.dhikrRemindersOn) return DhikrPlan.off;
    final pool = _ref.read(adhkarProvider).forNotifications;
    if (pool.isEmpty) return DhikrPlan.off;
    final locale = _ref.read(appLocaleProvider);
    final now = _ref.read(clockProvider)();
    final quiet = _quietUntil;
    return DhikrPlan(
      title: lookupAppLocalizations(locale).dhikrNotificationTitle,
      everyHours: settings.dhikrEveryHours,
      fromHour: dhikrFromHour,
      toHour: dhikrToHour,
      // Once over, the quiet is no longer part of the plan.
      quietUntil: quiet != null && quiet.isAfter(now) ? quiet : null,
      items: [for (final d in pool) dhikrText(d, locale.languageCode)],
    );
  }

  /// Taraweeh mode began (or ended): no dhikr for the next few hours (or
  /// back to the usual ones).
  Future<void> taraweeh({required bool on}) {
    _quietUntil = on ? _ref.read(clockProvider)().add(dhikrQuietDuringTaraweeh) : null;
    return sync();
  }

  /// Sends [plan] if it changed (or a day went by). Never throws: a
  /// reminder that cannot be scheduled must not break anything else.
  Future<void> sync({bool force = false}) async {
    final next = plan();
    final today = dateOnly(_ref.read(clockProvider)());
    // Off since the app started: leave the notification system alone
    // (turning off cancels explicitly).
    if (!force && next.isOff && _sent == null) return;
    if (!force && _sent == next && (next.isOff || _sentOn == today)) return;
    try {
      final l = lookupAppLocalizations(_ref.read(appLocaleProvider));
      await _ref.read(remindersProvider).scheduleDhikr(
            next,
            channelName: l.dhikrReminders,
            closeLabel: l.dhikrTapToClose,
          );
      _sent = next;
      _sentOn = today;
    } catch (e, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'dhikr reminders'));
    }
  }
}

/// Turn dhikr reminders on. First the card on the screen: if Android does
/// not allow it yet, explain and open its "Appear on top" setting. Then
/// permission to notify: without the card a dhikr is a notification, and
/// with it, a dhikr that comes while the phone is locked waits on the lock
/// screen too. False, with a message, if neither is allowed.
Future<bool> turnOnDhikrReminders(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final reminders = ref.read(remindersProvider);
  var onScreen = false;
  try {
    onScreen = await reminders.canShowOnScreen();
    if (!onScreen && context.mounted && await _explainOnScreen(context) == true) {
      onScreen = await reminders.requestShowOnScreen();
    }
  } catch (_) {
    // No such setting on this phone: notifications, then.
  }
  ref.invalidate(dhikrOnScreenProvider);
  bool notify;
  try {
    notify = await reminders.requestPermission();
  } catch (_) {
    notify = false;
  }
  if (!onScreen && !notify) {
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

/// Why Android's next screen is coming. True: go on to it; false: use
/// notifications instead.
Future<bool?> _explainOnScreen(BuildContext context) {
  final l = context.l10n;
  return showRubricSheet<bool>(
    context,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: l.dhikrReminders, explanation: l.dhikrOnScreenAsk),
          const SizedBox(height: RubricSpace.s4),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.continueAction)),
          const SizedBox(height: RubricSpace.s2),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.dhikrUseNotifications)),
        ],
      ),
    ),
  );
}

/// Open Android's "Appear on top" setting (to allow the card, or to take it
/// back), then read it again. Without the card a dhikr is a notification:
/// then ask for permission to notify, which turning on the card skipped.
Future<void> chooseDhikrOnScreen(WidgetRef ref) async {
  final reminders = ref.read(remindersProvider);
  try {
    if (!await reminders.requestShowOnScreen()) await reminders.requestPermission();
  } catch (_) {
    // No such setting on this phone.
  }
  ref.invalidate(dhikrOnScreenProvider);
}

/// A dhikr now, drawn the way the scheduled ones are.
Future<void> showDhikrNow(WidgetRef ref) async {
  final sync = ref.read(dhikrSyncProvider);
  final plan = sync.plan();
  if (plan.isOff) return;
  final l = lookupAppLocalizations(ref.read(appLocaleProvider));
  try {
    await ref.read(remindersProvider).showDhikr(plan, channelName: l.dhikrReminders, closeLabel: l.dhikrTapToClose);
  } catch (e, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'dhikr reminders'));
  }
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
    final onScreen = on ? ref.watch(dhikrOnScreenProvider).value : null;
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
        if (on) ...[
          RubricRow(
            label: l.dhikrHowOften,
            value: l.dhikrEvery(every),
            onTap: () => _chooseInterval(context, ref, every),
          ),
          // Known once Android has answered.
          if (onScreen != null)
            RubricRow(
              label: l.dhikrOnScreen,
              detail: onScreen ? l.dhikrOnScreenOn : l.dhikrOnScreenOff,
              onTap: () => chooseDhikrOnScreen(ref),
              trailing: Switch(value: onScreen, onChanged: (_) => chooseDhikrOnScreen(ref)),
            ),
          RubricRow(label: l.dhikrShowNow, onTap: () => showDhikrNow(ref)),
        ],
      ],
    );
  }
}
