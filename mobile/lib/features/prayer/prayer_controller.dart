import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/providers.dart';
import '../../core/prayer/prayer_times.dart';
import '../../data/cities.dart';
import '../../data/prayer_settings.dart';
import '../../l10n/l10n.dart';
import '../../services/location.dart';

/// A place found by the phone's location is moved only when the phone is
/// this far from it: the next town, not the next street.
const placeMovedKm = 25.0;

/// The prayer times' settings. A change is saved first and shown only once
/// it is safe (the rule of the reading store), then the adhans are
/// scheduled again.
class PrayerSettingsController extends Notifier<PrayerSettings> {
  @override
  PrayerSettings build() => ref.read(prayerStoreProvider).load();

  /// False, and nothing changed, if it could not be saved.
  Future<bool> update(PrayerSettings Function(PrayerSettings) change) async {
    final next = change(state);
    if (!await ref.read(prayerStoreProvider).save(next)) return false;
    state = next;
    // Not awaited: the first scheduling of a session takes a while, and
    // the screen should not wait for it.
    unawaited(ref.read(adhanSyncProvider).sync());
    return true;
  }

  /// The position the phone finds now becomes the place, named after the
  /// nearest town of the list. Null when done, else why not.
  Future<PlaceFailure?> useLocation() async {
    final found = await ref.read(locationProvider).locate();
    if (!found.found) return PlaceFailure.location(found.failure!);
    final cities = await ref.read(citiesProvider.future);
    final saved = await update((s) => s.withPlace(cities.located(found.latitude!, found.longitude!)));
    return saved ? null : const PlaceFailure.notSaved();
  }

  /// [city] becomes the place. False if it could not be saved.
  Future<bool> choose(City city) async {
    final cities = await ref.read(citiesProvider.future);
    return update((s) => s.withPlace(cities.chosen(city)));
  }

  /// The app is on screen again: a place that came from the phone's
  /// location follows the phone to another town. Asks the user nothing, and
  /// never moves a place they chose.
  Future<void> followLocation() async {
    final place = state.place;
    if (place == null || !place.fromLocation) return;
    try {
      final found = await ref.read(locationProvider).lastKnown();
      if (found == null || !found.found) return;
      final moved = distanceKm(place.latitude, place.longitude, found.latitude!, found.longitude!);
      if (moved < placeMovedKm) return;
      final cities = await ref.read(citiesProvider.future);
      await update((s) => s.withPlace(cities.located(found.latitude!, found.longitude!)));
    } catch (e, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'prayer times'));
    }
  }
}

/// Why a place could not be set.
class PlaceFailure {
  const PlaceFailure.location(LocationFailure this.location);
  const PlaceFailure.notSaved() : location = null;

  /// Null when the phone found a position that could not be saved.
  final LocationFailure? location;
}

/// A time of the day, as the phone's clock shows it.
typedef PrayerMoment = ({Prayer prayer, DateTime at});

/// Today's times and the next prayer.
class PrayerTimetable {
  const PrayerTimetable({required this.today, required this.next});

  /// The six times of today, in order.
  final List<PrayerMoment> today;

  /// The next prayer to be called: one of today's, or tomorrow's Fajr.
  /// Null only if tomorrow's times cannot be computed.
  final PrayerMoment? next;
}

/// The times of the day [now] is in, and the prayer that comes next, on the
/// phone's clock ([wallClock] turns an instant into it). Null without a
/// place, or where no times can be computed.
PrayerTimetable? prayerTimetable(PrayerSettings settings, DateTime now, DateTime Function(DateTime utc) wallClock) {
  final day = settings.timesOn(now);
  if (day == null) return null;
  final today = [for (final p in Prayer.values) (prayer: p, at: wallClock(day.at(p)))];
  PrayerMoment? next;
  for (final m in today) {
    if (m.prayer.isCalled && m.at.isAfter(now)) {
      next = m;
      break;
    }
  }
  if (next == null) {
    final tomorrow = settings.timesOn(DateTime(now.year, now.month, now.day + 1));
    if (tomorrow != null) next = (prayer: Prayer.fajr, at: wallClock(tomorrow.at(Prayer.fajr)));
  }
  return PrayerTimetable(today: today, next: next);
}

String prayerName(AppLocalizations l, Prayer prayer) => switch (prayer) {
      Prayer.fajr => l.prayerFajr,
      Prayer.sunrise => l.prayerSunrise,
      Prayer.dhuhr => l.prayerDhuhr,
      Prayer.asr => l.prayerAsr,
      Prayer.maghrib => l.prayerMaghrib,
      Prayer.isha => l.prayerIsha,
    };

String alertLabel(AppLocalizations l, AdhanAlert alert) => switch (alert) {
      AdhanAlert.sound => l.alertSound,
      AdhanAlert.vibrate => l.alertVibrate,
      AdhanAlert.silent => l.alertSilent,
      AdhanAlert.off => l.alertOff,
    };

String soundLabel(AppLocalizations l, AdhanSound sound) => switch (sound) {
      AdhanSound.full => l.adhanSoundFull,
      AdhanSound.takbir => l.adhanSoundTakbir,
    };

String asrLabel(AppLocalizations l, AsrSchool school) => switch (school) {
      AsrSchool.standard => l.asrStandard,
      AsrSchool.hanafi => l.asrHanafi,
    };

String methodName(AppLocalizations l, PrayerMethod method) => switch (method) {
      PrayerMethod.muslimWorldLeague => l.methodMuslimWorldLeague,
      PrayerMethod.tunisia => l.methodTunisia,
      PrayerMethod.algeria => l.methodAlgeria,
      PrayerMethod.morocco => l.methodMorocco,
      PrayerMethod.egypt => l.methodEgypt,
      PrayerMethod.ummAlQura => l.methodUmmAlQura,
      PrayerMethod.gulf => l.methodGulf,
      PrayerMethod.dubai => l.methodDubai,
      PrayerMethod.kuwait => l.methodKuwait,
      PrayerMethod.qatar => l.methodQatar,
      PrayerMethod.jordan => l.methodJordan,
      PrayerMethod.turkiye => l.methodTurkiye,
      PrayerMethod.france => l.methodFrance,
      PrayerMethod.karachi => l.methodKarachi,
      PrayerMethod.northAmerica => l.methodNorthAmerica,
      PrayerMethod.moonsighting => l.methodMoonsighting,
      PrayerMethod.singapore => l.methodSingapore,
      PrayerMethod.indonesia => l.methodIndonesia,
      PrayerMethod.russia => l.methodRussia,
      PrayerMethod.portugal => l.methodPortugal,
      PrayerMethod.tehran => l.methodTehran,
      PrayerMethod.jafari => l.methodJafari,
    };

/// "in 1 h 12 min", "in 12 min", "now": how long until [at], to the minute
/// (rounded up, so "in 1 min" lasts until the time itself).
String countdownLabel(AppLocalizations l, DateTime now, DateTime at) {
  final minutes = (at.difference(now).inSeconds / 60).ceil();
  if (minutes <= 0) return l.prayerNow;
  final h = minutes ~/ 60, m = minutes % 60;
  return l.prayerIn(h == 0
      ? l.durationMinutes(m)
      : m == 0
          ? l.durationHours(h)
          : l.durationHoursMinutes(h, m));
}

/// "+2 min", "−3 min": minutes added to a time (a real minus sign).
String offsetLabel(AppLocalizations l, int minutes) =>
    minutes == 0 ? l.adjustTimesNone : l.offsetMinutes(minutes > 0 ? '+$minutes' : '−${-minutes}');

/// U+202F, the narrow no-break space of "12:03 PM" in the date symbols.
final _narrowSpace = String.fromCharCode(0x202F);

/// [at] as a clock shows it, where there is no screen to ask (a
/// notification): in [languageCode], 24 hours if the phone is set so.
String formatClock(DateTime at, String languageCode) {
  try {
    final use24 = WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat;
    // A plain space before AM or PM, as the screens write it (the date
    // symbols use a narrow no-break space).
    final format = use24 ? DateFormat.Hm(languageCode) : DateFormat.jm(languageCode);
    return format.format(at).replaceAll(_narrowSpace, ' ');
  } catch (_) {
    // The language's date symbols are not loaded: plain digits never fail.
    return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }
}
