import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/components/choice_sheet.dart';
import '../../app/components/notice.dart';
import '../../app/components/settings_group.dart';
import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../core/prayer/prayer_times.dart';
import '../../data/prayer_settings.dart';
import '../../l10n/l10n.dart';
import 'adhan_sync.dart';
import 'place_screen.dart';
import 'prayer_controller.dart';

/// A time as the phone shows times (12 or 24 hours, in the interface
/// language).
String clockLabel(BuildContext context, DateTime at) => TimeOfDay.fromDateTime(at).format(context);

/// The place and its country: "Tunis, Tunisia". The country comes from the
/// list of towns, so it is missing until the list is read (then the town
/// alone is shown).
String placeLabel(AppLocalizations l, WidgetRef ref, Place place) {
  final language = l.localeName;
  final country = ref.watch(citiesProvider).value?.countryName(place.countryCode, language);
  final name = place.name(language);
  return country == null || country == name ? name : l.placeAndCountry(name, country);
}

/// Prayer times: the next prayer, today's times with each prayer's adhan,
/// the adhan's settings, and how the times are computed. Before a place is
/// known, how to give one.
class PrayerScreen extends ConsumerStatefulWidget {
  const PrayerScreen({super.key});

  @override
  ConsumerState<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends ConsumerState<PrayerScreen> {
  /// The countdown is to the minute: looking twice a minute keeps it true.
  Timer? _tick;
  late final AppLifecycleListener _lifecycle;
  bool _locating = false;
  PlaceFailure? _failure;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Back from the phone's settings: what Android allows may have changed.
    _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(adhanStatusProvider));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _failure = null;
    });
    final failure = await ref.read(prayerSettingsProvider.notifier).useLocation();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _failure = failure;
    });
  }

  Future<void> _update(PrayerSettings Function(PrayerSettings) change) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final saved = await ref.read(prayerSettingsProvider.notifier).update(change);
    if (!saved) messenger.showSnackBar(SnackBar(content: Text(l.prayerNotSaved)));
  }

  Future<void> _chooseAlert(Prayer prayer, AdhanAlert current) async {
    final l = context.l10n;
    final alert = await showChoiceSheet<AdhanAlert>(
      context,
      title: l.adhanFor(prayerName(l, prayer)),
      explanation: l.adhanAlertExplanation,
      options: const [AdhanAlert.sound, AdhanAlert.vibrate, AdhanAlert.silent, AdhanAlert.off],
      current: current,
      label: (a) => alertLabel(l, a),
    );
    if (alert != null && alert != current) await _update((s) => s.withAlert(prayer, alert));
  }

  Future<void> _chooseSound(AdhanSound current) async {
    final l = context.l10n;
    final sound = await showChoiceSheet<AdhanSound>(
      context,
      title: l.adhanSound,
      explanation: l.adhanSoundExplanation,
      options: AdhanSound.values,
      current: current,
      label: (s) => soundLabel(l, s),
    );
    if (sound != null && sound != current) await _update((s) => s.withSound(sound));
  }

  Future<void> _chooseMethod(PrayerSettings settings) async {
    final l = context.l10n;
    final automatic = PrayerMethod.forCountry(settings.place?.countryCode);
    // Null is "automatic": a sheet returns null when dismissed, so the
    // options are wrapped.
    final choice = await showChoiceSheet<({PrayerMethod? method})>(
      context,
      title: l.prayerMethod,
      explanation: l.prayerMethodExplanation,
      options: [(method: null), for (final m in PrayerMethod.values) (method: m)],
      current: (method: settings.method),
      label: (o) => o.method == null ? l.methodAutomatic(methodName(l, automatic)) : methodName(l, o.method!),
    );
    if (choice != null && choice.method != settings.method) await _update((s) => s.withMethod(choice.method));
  }

  Future<void> _chooseAsr(PrayerSettings settings) async {
    final l = context.l10n;
    final school = await showChoiceSheet<AsrSchool>(
      context,
      title: l.asrTime,
      explanation: l.asrExplanation,
      options: AsrSchool.values,
      current: settings.effectiveAsr,
      label: (s) => asrLabel(l, s),
    );
    if (school != null && school != settings.effectiveAsr) await _update((s) => s.withAsr(school));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final settings = ref.watch(prayerSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.prayerTimes)),
      body: settings.place == null ? _intro(context) : _times(context, settings, settings.place!),
    );
  }

  /// No place yet: what the screen is for, and the two ways to give one.
  Widget _intro(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return ListView(
      // Its own list: the times, once there is a place, open at their top
      // wherever this one was scrolled to.
      key: const ValueKey('intro'),
      padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s6, RubricSpace.gutter, RubricSpace.s8),
      children: [
        Semantics(
          header: true,
          child: Text(l.prayerIntroTitle, style: RubricText.sheetTitle.copyWith(color: c.ink)),
        ),
        const SizedBox(height: RubricSpace.s2),
        Text(l.prayerIntroBody, style: RubricText.label.copyWith(color: c.inkSecondary)),
        const SizedBox(height: RubricSpace.s6),
        FilledButton.icon(
          onPressed: _locating ? null : _locate,
          icon: _locating
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location, size: 20),
          label: Text(_locating ? l.locating : l.useMyLocation),
        ),
        const SizedBox(height: RubricSpace.s2),
        OutlinedButton(
          onPressed: () => AppRoutes.place(context, search: true),
          child: Text(l.chooseCity),
        ),
        if (_failure != null) ...[
          const SizedBox(height: RubricSpace.s4),
          PlaceFailureNotice(failure: _failure!),
        ],
      ],
    );
  }

  Widget _times(BuildContext context, PrayerSettings settings, Place place) {
    final l = context.l10n;
    final c = context.colors;
    final now = ref.watch(clockProvider)();
    final table = prayerTimetable(settings, now, ref.watch(wallClockProvider));
    final next = table?.next;
    final status = settings.adhanOn ? ref.watch(adhanStatusProvider).value : null;
    final adjusted = Prayer.called.where((p) => settings.offsetOf(p) != 0).length;
    final secondary = RubricText.label.copyWith(color: c.inkSecondary);
    return ListView(
      key: const ValueKey('times'),
      padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s2, RubricSpace.gutter, RubricSpace.s8),
      children: [
        if (table == null)
          Notice(icon: Icons.info_outline, title: l.prayerUnavailable)
        else ...[
          if (next != null)
            // One item for a screen reader: "Next prayer, Asr, 3:42 PM, in 1 h 12 min".
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.prayerNextLabel.toUpperCase(),
                    style: RubricText.overlineFor(context).copyWith(color: c.inkSecondary),
                  ),
                  const SizedBox(height: RubricSpace.s1),
                  Text(prayerName(l, next.prayer), style: RubricText.titleLg.copyWith(color: c.ink)),
                  Text('${clockLabel(context, next.at)} · ${countdownLabel(l, now, next.at)}', style: secondary),
                ],
              ),
            ),
          RubricGroup(
            label: DateFormat.MMMMEEEEd(l.localeName).format(now),
            children: [
              for (final moment in table.today)
                _PrayerRow(
                  name: prayerName(l, moment.prayer),
                  time: clockLabel(context, moment.at),
                  adhanOn: settings.adhanOn,
                  alert: settings.adhanOn && moment.prayer.isCalled ? settings.alertOf(moment.prayer) : null,
                  next: moment == next,
                  passed: !moment.at.isAfter(now),
                  onTap: settings.adhanOn && moment.prayer.isCalled
                      ? () => _chooseAlert(moment.prayer, settings.alertOf(moment.prayer))
                      : null,
                ),
            ],
          ),
        ],
        RubricGroup(
          label: l.adhan,
          children: [
            RubricRow(
              label: l.adhan,
              detail: settings.adhanOn ? l.adhanOnDetail : l.adhanOffDetail,
              onTap: () => settings.adhanOn ? turnOffAdhan(context, ref) : turnOnAdhan(context, ref),
              trailing: Switch(
                value: settings.adhanOn,
                onChanged: (on) => on ? turnOnAdhan(context, ref) : turnOffAdhan(context, ref),
              ),
            ),
            if (settings.adhanOn) ...[
              RubricRow(
                label: l.adhanSound,
                value: soundLabel(l, settings.sound),
                onTap: () => _chooseSound(settings.sound),
              ),
              RubricRow(
                label: l.adhanTest,
                detail: l.adhanTestDetail,
                trailing: Icon(Icons.play_arrow_outlined, color: c.inkSecondary),
                onTap: () => testAdhan(context, ref),
              ),
            ],
          ],
        ),
        if (status != null && !status.allowed) ...[
          const SizedBox(height: RubricSpace.s4),
          Notice(icon: Icons.notifications_off_outlined, title: l.adhanBlockedTitle, body: l.reminderBlocked),
        ] else if (status != null && !status.exact) ...[
          const SizedBox(height: RubricSpace.s4),
          Notice(
            icon: Icons.schedule,
            title: l.adhanLateTitle,
            body: l.adhanLateBody,
            actionLabel: l.adhanAllowAlarms,
            onAction: () => allowAdhanAlarms(ref),
          ),
        ],
        RubricGroup(
          label: l.groupCalculation,
          children: [
            RubricRow(
              label: l.prayerPlace,
              detail: place.fromLocation ? l.prayerPlaceLocated : null,
              value: placeLabel(l, ref, place),
              onTap: () => AppRoutes.place(context),
            ),
            RubricRow(
              label: l.prayerMethod,
              value: methodName(l, settings.effectiveMethod),
              onTap: () => _chooseMethod(settings),
            ),
            RubricRow(
              label: l.asrTime,
              value: asrLabel(l, settings.effectiveAsr),
              onTap: () => _chooseAsr(settings),
            ),
            RubricRow(
              label: l.adjustTimes,
              value: adjusted == 0 ? l.adjustTimesNone : l.adjustTimesSome(adjusted),
              onTap: () => showAdjustSheet(context),
            ),
          ],
        ),
        const SizedBox(height: RubricSpace.s4),
        Text(l.prayerNote, style: RubricText.caption.copyWith(color: c.inkSecondary)),
      ],
    );
  }
}

/// One time of the day: its name, its time, and how its adhan is called
/// (while the adhan is on). The next prayer stands out in weight; the times
/// already past rest in `ink-secondary`.
class _PrayerRow extends StatelessWidget {
  const _PrayerRow({
    required this.name,
    required this.time,
    required this.adhanOn,
    required this.alert,
    required this.next,
    required this.passed,
    required this.onTap,
  });

  final String name;
  final String time;
  final bool adhanOn;

  /// Null where there is no adhan to show (the sunrise, or the adhan off).
  final AdhanAlert? alert;
  final bool next;
  final bool passed;
  final VoidCallback? onTap;

  static IconData icon(AdhanAlert alert) => switch (alert) {
        AdhanAlert.sound => Icons.volume_up_outlined,
        AdhanAlert.vibrate => Icons.vibration,
        AdhanAlert.silent => Icons.notifications_none,
        AdhanAlert.off => Icons.notifications_off_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final style = RubricText.label.copyWith(color: passed ? c.inkSecondary : c.ink);
    return MergeSemantics(
      child: Semantics(
        selected: next,
        onTapHint: onTap == null ? null : l.hintAdhanAlert,
        child: InkWell(
          onTap: onTap,
          highlightColor: c.surfaceRaised,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s4, vertical: RubricSpace.s2),
              // The name at one end, the time and its icon at the other; with
              // very large text on a narrow phone, the time goes under the name.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runAlignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: RubricSpace.s3,
                children: [
                  Text(name, style: next ? style.weighted(500) : style),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(time, style: next ? style.weighted(500) : style),
                      // While the adhan is on, the times stay in one column
                      // whether or not a row has an icon (the sunrise has none).
                      if (adhanOn) ...[
                        const SizedBox(width: RubricSpace.s3),
                        SizedBox(
                          width: 24,
                          child: alert == null
                              ? null
                              : Icon(
                                  icon(alert!),
                                  size: 22,
                                  color: c.inkSecondary,
                                  semanticLabel: l.semAdhanAlert(alertLabel(l, alert!)),
                                ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Minutes added to each prayer's time, to match the local mosque.
Future<void> showAdjustSheet(BuildContext context) => showRubricSheet<void>(
      context,
      builder: (context) => const _AdjustSheet(),
    );

class _AdjustSheet extends ConsumerWidget {
  const _AdjustSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final settings = ref.watch(prayerSettingsProvider);
    final controller = ref.read(prayerSettingsProvider.notifier);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(title: l.adjustTimes, explanation: l.adjustExplanation),
          const SizedBox(height: RubricSpace.s4),
          RubricGroup(
            children: [
              for (final prayer in Prayer.called)
                Builder(builder: (context) {
                  final name = prayerName(l, prayer);
                  final minutes = settings.offsetOf(prayer);
                  void move(int by) => controller.update((s) => s.withOffset(prayer, minutes + by));
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(start: RubricSpace.s4, end: RubricSpace.s1),
                    child: Row(
                      children: [
                        Expanded(
                          child: MergeSemantics(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(name, style: RubricText.label.copyWith(color: c.ink)),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    offsetLabel(l, minutes),
                                    style: RubricText.caption.copyWith(color: c.inkSecondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l.semEarlier(name),
                          onPressed: minutes > -maxPrayerOffset ? () => move(-1) : null,
                          icon: const Icon(Icons.remove),
                        ),
                        IconButton(
                          tooltip: l.semLater(name),
                          onPressed: minutes < maxPrayerOffset ? () => move(1) : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }
}
