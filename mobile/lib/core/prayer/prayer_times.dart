/// The prayer times of a day at a place, computed on the phone from the
/// sun's position (the `adhan_dart` package, after Jean Meeus's
/// "Astronomical Algorithms"). Nothing is fetched: the same place, day and
/// rules always give the same times.
///
/// The times are instants (UTC). What the phone's clock shows for them is
/// the caller's business.
library;

import 'dart:math' as math;

import 'package:adhan_dart/adhan_dart.dart' as adhan;

/// The times of a day, in order. [sunrise] ends the time of Fajr: it is
/// shown, and never called.
enum Prayer {
  fajr,
  sunrise,
  dhuhr,
  asr,
  maghrib,
  isha;

  /// The five prayers, each with its adhan.
  static const called = [fajr, dhuhr, asr, maghrib, isha];

  bool get isCalled => this != sunrise;
}

/// Who sets the angles of Fajr and Isha (and a few fixed minutes): the
/// authority a country's mosques follow.
enum PrayerMethod {
  muslimWorldLeague,
  tunisia,
  algeria,
  morocco,
  egypt,
  ummAlQura,
  gulf,
  dubai,
  kuwait,
  qatar,
  jordan,
  turkiye,
  france,
  karachi,
  northAmerica,
  moonsighting,
  singapore,
  indonesia,
  russia,
  portugal,
  tehran,
  jafari;

  /// The method the mosques of a country ([countryCode]: ISO 3166, two
  /// letters) usually follow; the Muslim World League's elsewhere.
  static PrayerMethod forCountry(String? countryCode) => _byCountry[countryCode?.toUpperCase()] ?? muslimWorldLeague;

  static const _byCountry = <String, PrayerMethod>{
    'TN': tunisia,
    'DZ': algeria,
    'MA': morocco,
    'EG': egypt,
    'LY': egypt,
    'SD': egypt,
    'SY': egypt,
    'LB': egypt,
    'PS': egypt,
    'IQ': egypt,
    'SA': ummAlQura,
    'YE': ummAlQura,
    'BH': gulf,
    'OM': gulf,
    'AE': dubai,
    'KW': kuwait,
    'QA': qatar,
    'JO': jordan,
    'TR': turkiye,
    'FR': france,
    'PK': karachi,
    'IN': karachi,
    'BD': karachi,
    'AF': karachi,
    'US': northAmerica,
    'CA': northAmerica,
    'GB': moonsighting,
    'IE': moonsighting,
    'SG': singapore,
    'MY': singapore,
    'BN': singapore,
    'ID': indonesia,
    'RU': russia,
    'PT': portugal,
    'IR': tehran,
  };

  adhan.CalculationParameters get _parameters => switch (this) {
        muslimWorldLeague => adhan.CalculationMethodParameters.muslimWorldLeague(),
        tunisia => adhan.CalculationMethodParameters.tunisia(),
        algeria => adhan.CalculationMethodParameters.algerian(),
        morocco => adhan.CalculationMethodParameters.morocco(),
        egypt => adhan.CalculationMethodParameters.egyptian(),
        ummAlQura => adhan.CalculationMethodParameters.ummAlQura(),
        gulf => adhan.CalculationMethodParameters.gulfRegion(),
        dubai => adhan.CalculationMethodParameters.dubai(),
        kuwait => adhan.CalculationMethodParameters.kuwait(),
        qatar => adhan.CalculationMethodParameters.qatar(),
        jordan => adhan.CalculationMethodParameters.jordan(),
        turkiye => adhan.CalculationMethodParameters.turkiye(),
        france => adhan.CalculationMethodParameters.france(),
        karachi => adhan.CalculationMethodParameters.karachi(),
        northAmerica => adhan.CalculationMethodParameters.northAmerica(),
        moonsighting => adhan.CalculationMethodParameters.moonsightingCommittee(),
        singapore => adhan.CalculationMethodParameters.singapore(),
        indonesia => adhan.CalculationMethodParameters.indonesian(),
        russia => adhan.CalculationMethodParameters.russia(),
        portugal => adhan.CalculationMethodParameters.portugal(),
        tehran => adhan.CalculationMethodParameters.tehran(),
        jafari => adhan.CalculationMethodParameters.jafari(),
      };
}

/// When Asr begins: when a thing's shadow is as long as the thing itself
/// (the Maliki, Shafi'i and Hanbali schools), or twice as long (the Hanafi).
enum AsrSchool {
  standard,
  hanafi;

  /// The school most mosques of a country follow for Asr.
  static AsrSchool forCountry(String? countryCode) =>
      const {'PK', 'IN', 'BD', 'AF'}.contains(countryCode?.toUpperCase()) ? hanafi : standard;
}

/// How far a time may be moved to match the local mosque, in minutes.
const maxPrayerOffset = 30;

/// One day's times at one place.
class PrayerDay {
  PrayerDay._(this.year, this.month, this.day, this._times);

  /// The calendar day at the place.
  final int year;
  final int month;
  final int day;

  final Map<Prayer, DateTime> _times;

  /// When [prayer] begins: an instant (UTC), on the minute.
  DateTime at(Prayer prayer) => _times[prayer]!;
}

/// The times of the calendar day [year]-[month]-[day] at [latitude],
/// [longitude] (degrees, north and east positive), by [method] and [asr],
/// each moved by its [offsets] (minutes, within [maxPrayerOffset]).
///
/// Far north, where the sky never darkens enough in summer, Fajr and Isha
/// take a share of the night instead (a seventh above 48°). Where the sun
/// does not rise or set at all that day, the nearest latitude where it does
/// stands in, at the same longitude. Null if no place gives such times.
PrayerDay? prayerDay({
  required int year,
  required int month,
  required int day,
  required double latitude,
  required double longitude,
  required PrayerMethod method,
  AsrSchool asr = AsrSchool.standard,
  Map<Prayer, int> offsets = const {},
}) {
  if (!(latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180)) return null;
  final towardsEquator = latitude > 0 ? -_latitudeStep : _latitudeStep;
  for (var lat = latitude; lat.abs() >= _nearestLatitudeFloor || lat == latitude; lat += towardsEquator) {
    final times = _timesAt(year, month, day, lat, longitude, method, asr, offsets);
    if (times != null) return PrayerDay._(year, month, day, Map.unmodifiable(times));
  }
  return null;
}

/// How far a polar place is moved at a time to find a sunrise and a sunset,
/// and where the search gives up (no day lacks them below this latitude).
const _latitudeStep = 0.5;
const _nearestLatitudeFloor = 60.0;

Map<Prayer, DateTime>? _timesAt(
  int year,
  int month,
  int day,
  double latitude,
  double longitude,
  PrayerMethod method,
  AsrSchool asr,
  Map<Prayer, int> offsets,
) {
  try {
    final coordinates = adhan.Coordinates(latitude, longitude);
    int offset(Prayer p) => (offsets[p] ?? 0).clamp(-maxPrayerOffset, maxPrayerOffset);
    final parameters = method._parameters.copyWith(
      madhab: asr == AsrSchool.hanafi ? adhan.Madhab.hanafi : adhan.Madhab.shafi,
      highLatitudeRule: adhan.HighLatitudeRule.recommended(coordinates),
      adjustments: {
        adhan.Prayer.fajr: offset(Prayer.fajr),
        adhan.Prayer.sunrise: offset(Prayer.sunrise),
        adhan.Prayer.dhuhr: offset(Prayer.dhuhr),
        adhan.Prayer.asr: offset(Prayer.asr),
        adhan.Prayer.maghrib: offset(Prayer.maghrib),
        adhan.Prayer.isha: offset(Prayer.isha),
      },
    );
    final date = DateTime.utc(year, month, day);
    final times = adhan.PrayerTimes(date: date, coordinates: coordinates, calculationParameters: parameters);
    final result = {
      Prayer.fajr: times.fajr,
      Prayer.sunrise: times.sunrise,
      Prayer.dhuhr: times.dhuhr,
      Prayer.asr: times.asr,
      Prayer.maghrib: times.maghrib,
      Prayer.isha: times.isha,
    };
    // A timetable: each time after the one before, all within the day and
    // the night that follows it, wherever on Earth the day is.
    for (var i = 1; i < Prayer.values.length; i++) {
      if (!result[Prayer.values[i]]!.isAfter(result[Prayer.values[i - 1]]!)) return null;
    }
    if (times.fajr.isBefore(date.subtract(const Duration(hours: 14)))) return null;
    if (times.isha.isAfter(date.add(const Duration(hours: 38)))) return null;
    if (times.isha.difference(times.fajr) >= const Duration(hours: 24)) return null;
    return result;
  } on Object {
    // No sunrise or sunset to compute from (the package throws on those).
    return null;
  }
}

/// The distance between two places, in kilometres (a sphere is near enough
/// to tell one town from the next).
double distanceKm(double latitudeA, double longitudeA, double latitudeB, double longitudeB) {
  const radius = 6371.0;
  double radians(double degrees) => degrees * math.pi / 180;
  final p1 = radians(latitudeA), p2 = radians(latitudeB);
  final dp = p2 - p1, dl = radians(longitudeB - longitudeA);
  final h = math.pow(math.sin(dp / 2), 2) + math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  return 2 * radius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
}
