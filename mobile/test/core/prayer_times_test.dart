import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/prayer/prayer_times.dart';

/// Minutes between two instants.
int apart(DateTime a, DateTime b) => a.difference(b).inMinutes.abs();

void main() {
  const tunisLat = 36.8065, tunisLon = 10.1815;

  PrayerDay tunis(int year, int month, int day,
          {PrayerMethod method = PrayerMethod.tunisia,
          AsrSchool asr = AsrSchool.standard,
          Map<Prayer, int> offsets = const {}}) =>
      prayerDay(
        year: year,
        month: month,
        day: day,
        latitude: tunisLat,
        longitude: tunisLon,
        method: method,
        asr: asr,
        offsets: offsets,
      )!;

  group('the times of a day', () {
    // The expected instants come from the NOAA solar equations, worked out
    // apart from the package the app computes with: sunrise and sunset at
    // -0.833°, Fajr and Isha at 18° below the horizon (Tunisia's angles),
    // Asr at a shadow of one length.
    test('Tunis, 10 November 2026', () {
      final day = tunis(2026, 11, 10);
      final expected = {
        Prayer.fajr: DateTime.utc(2026, 11, 10, 4, 23),
        Prayer.sunrise: DateTime.utc(2026, 11, 10, 5, 52),
        Prayer.dhuhr: DateTime.utc(2026, 11, 10, 11, 3),
        Prayer.asr: DateTime.utc(2026, 11, 10, 13, 53),
        Prayer.maghrib: DateTime.utc(2026, 11, 10, 16, 14),
        Prayer.isha: DateTime.utc(2026, 11, 10, 17, 43),
      };
      for (final MapEntry(key: prayer, value: at) in expected.entries) {
        expect(apart(day.at(prayer), at), lessThanOrEqualTo(1), reason: '${prayer.name}: ${day.at(prayer)}');
      }
    });

    test('Tunis, the longest day', () {
      final day = tunis(2026, 6, 21);
      final expected = {
        Prayer.fajr: DateTime.utc(2026, 6, 21, 2, 8),
        Prayer.sunrise: DateTime.utc(2026, 6, 21, 4, 0),
        Prayer.dhuhr: DateTime.utc(2026, 6, 21, 11, 21),
        Prayer.asr: DateTime.utc(2026, 6, 21, 15, 13),
        Prayer.maghrib: DateTime.utc(2026, 6, 21, 18, 42),
        Prayer.isha: DateTime.utc(2026, 6, 21, 20, 34),
      };
      for (final MapEntry(key: prayer, value: at) in expected.entries) {
        expect(apart(day.at(prayer), at), lessThanOrEqualTo(1), reason: '${prayer.name}: ${day.at(prayer)}');
      }
    });

    test('Makkah, Umm al-Qura: Isha an hour and a half after Maghrib', () {
      final day = prayerDay(
        year: 2026,
        month: 11,
        day: 10,
        latitude: 21.4225,
        longitude: 39.8262,
        method: PrayerMethod.ummAlQura,
      )!;
      expect(apart(day.at(Prayer.sunrise), DateTime.utc(2026, 11, 10, 3, 29)), lessThanOrEqualTo(1));
      expect(apart(day.at(Prayer.dhuhr), DateTime.utc(2026, 11, 10, 9, 5)), lessThanOrEqualTo(1));
      expect(apart(day.at(Prayer.asr), DateTime.utc(2026, 11, 10, 12, 17)), lessThanOrEqualTo(1));
      expect(apart(day.at(Prayer.maghrib), DateTime.utc(2026, 11, 10, 14, 40)), lessThanOrEqualTo(1));
      expect(day.at(Prayer.isha).difference(day.at(Prayer.maghrib)), const Duration(minutes: 90));
    });

    test('south of the equator and east of Greenwich: Jakarta, the day before in UTC', () {
      final day = prayerDay(
        year: 2026,
        month: 11,
        day: 10,
        latitude: -6.2088,
        longitude: 106.8456,
        method: PrayerMethod.indonesia,
      )!;
      // Sunrise on the 10th in Jakarta (05:25, UTC+7) is 22:25 on the 9th in UTC.
      expect(apart(day.at(Prayer.sunrise), DateTime.utc(2026, 11, 9, 22, 25)), lessThanOrEqualTo(1));
      expect(apart(day.at(Prayer.maghrib), DateTime.utc(2026, 11, 10, 10, 48)), lessThanOrEqualTo(1));
    });

    test('west of Greenwich: Honolulu, the day after in UTC', () {
      final day = prayerDay(
        year: 2026,
        month: 11,
        day: 10,
        latitude: 21.3069,
        longitude: -157.8583,
        method: PrayerMethod.northAmerica,
      )!;
      // Maghrib on the 10th in Honolulu (17:51, UTC-10) is 03:51 on the 11th in UTC.
      expect(apart(day.at(Prayer.maghrib), DateTime.utc(2026, 11, 11, 3, 51)), lessThanOrEqualTo(2));
    });

    test('on the minute, each after the one before', () {
      for (final month in [1, 3, 6, 9, 12]) {
        final day = tunis(2026, month, 15);
        for (var i = 0; i < Prayer.values.length; i++) {
          final at = day.at(Prayer.values[i]);
          expect(at.isUtc, isTrue);
          expect(at.second, 0);
          if (i > 0) expect(at.isAfter(day.at(Prayer.values[i - 1])), isTrue, reason: '$month: ${Prayer.values[i]}');
        }
      }
    });

    test('the sunrise is shown, not called', () {
      expect(Prayer.called, [Prayer.fajr, Prayer.dhuhr, Prayer.asr, Prayer.maghrib, Prayer.isha]);
      expect(Prayer.sunrise.isCalled, isFalse);
    });
  });

  group('the rules', () {
    test('every method gives a day of times in Tunis', () {
      for (final method in PrayerMethod.values) {
        expect(
          prayerDay(year: 2026, month: 11, day: 10, latitude: tunisLat, longitude: tunisLon, method: method),
          isNotNull,
          reason: method.name,
        );
      }
    });

    test('a lower angle means a later Fajr and an earlier Isha: France (12°) against Tunisia (18°)', () {
      final tunisia = tunis(2026, 11, 10), france = tunis(2026, 11, 10, method: PrayerMethod.france);
      expect(france.at(Prayer.fajr).isAfter(tunisia.at(Prayer.fajr)), isTrue);
      expect(france.at(Prayer.isha).isBefore(tunisia.at(Prayer.isha)), isTrue);
      expect(france.at(Prayer.maghrib), tunisia.at(Prayer.maghrib), reason: 'the sun sets when it sets');
    });

    test('the Hanafi Asr is later, and nothing else moves', () {
      final standard = tunis(2026, 11, 10), hanafi = tunis(2026, 11, 10, asr: AsrSchool.hanafi);
      // The NOAA equations again: a shadow of two lengths at 14:35 UTC.
      expect(apart(hanafi.at(Prayer.asr), DateTime.utc(2026, 11, 10, 14, 35)), lessThanOrEqualTo(1));
      for (final p in Prayer.values) {
        if (p != Prayer.asr) expect(hanafi.at(p), standard.at(p));
      }
    });

    test('a time moved to match the mosque, within half an hour', () {
      final plain = tunis(2026, 11, 10);
      final moved = tunis(2026, 11, 10, offsets: {Prayer.fajr: 3, Prayer.isha: -2, Prayer.dhuhr: 90});
      expect(moved.at(Prayer.fajr), plain.at(Prayer.fajr).add(const Duration(minutes: 3)));
      expect(moved.at(Prayer.isha), plain.at(Prayer.isha).subtract(const Duration(minutes: 2)));
      expect(moved.at(Prayer.dhuhr), plain.at(Prayer.dhuhr).add(const Duration(minutes: maxPrayerOffset)));
      expect(moved.at(Prayer.asr), plain.at(Prayer.asr));
    });

    test('a country has its method, and the rest of the world the Muslim World League', () {
      expect(PrayerMethod.forCountry('TN'), PrayerMethod.tunisia);
      expect(PrayerMethod.forCountry('tn'), PrayerMethod.tunisia);
      expect(PrayerMethod.forCountry('DZ'), PrayerMethod.algeria);
      expect(PrayerMethod.forCountry('MA'), PrayerMethod.morocco);
      expect(PrayerMethod.forCountry('FR'), PrayerMethod.france);
      expect(PrayerMethod.forCountry('SA'), PrayerMethod.ummAlQura);
      expect(PrayerMethod.forCountry('EG'), PrayerMethod.egypt);
      expect(PrayerMethod.forCountry('DE'), PrayerMethod.muslimWorldLeague);
      expect(PrayerMethod.forCountry(null), PrayerMethod.muslimWorldLeague);
      expect(AsrSchool.forCountry('PK'), AsrSchool.hanafi);
      expect(AsrSchool.forCountry('TN'), AsrSchool.standard);
      expect(AsrSchool.forCountry(null), AsrSchool.standard);
    });
  });

  group('far north', () {
    test('Oslo in June: the sky never darkens, Fajr and Isha take a share of the night', () {
      final day = prayerDay(
          year: 2026, month: 6, day: 21, latitude: 59.9139, longitude: 10.7522, method: PrayerMethod.tunisia)!;
      final night = day.at(Prayer.sunrise).add(const Duration(days: 1)).difference(day.at(Prayer.maghrib));
      expect(night.inHours, lessThan(6));
      expect(day.at(Prayer.sunrise).difference(day.at(Prayer.fajr)).inMinutes, closeTo(night.inMinutes / 7, 3));
      expect(day.at(Prayer.isha).difference(day.at(Prayer.maghrib)).inMinutes, closeTo(night.inMinutes / 7, 3));
    });

    test('Tromsø: no sunset in June, no sunrise in December, and still a day of times', () {
      for (final month in [6, 12]) {
        final day = prayerDay(
          year: 2026,
          month: month,
          day: 21,
          latitude: 69.6492,
          longitude: 18.9553,
          method: PrayerMethod.muslimWorldLeague,
        );
        expect(day, isNotNull, reason: 'month $month');
        // Around solar noon, as at any longitude 19° east.
        expect(apart(day!.at(Prayer.dhuhr), DateTime.utc(2026, month, 21, 10, 45)), lessThan(15));
      }
    });

    test('the pole itself, and nowhere', () {
      expect(
        prayerDay(year: 2026, month: 6, day: 21, latitude: 90, longitude: 0, method: PrayerMethod.muslimWorldLeague),
        isNotNull,
      );
      expect(
        prayerDay(year: 2026, month: 6, day: 21, latitude: 91, longitude: 0, method: PrayerMethod.muslimWorldLeague),
        isNull,
      );
      expect(
        prayerDay(
            year: 2026, month: 6, day: 21, latitude: double.nan, longitude: 0, method: PrayerMethod.muslimWorldLeague),
        isNull,
      );
    });
  });

  test('distance: Tunis to Sfax is about 235 km, and a place to itself nothing', () {
    expect(distanceKm(tunisLat, tunisLon, 34.7406, 10.7603), closeTo(235, 3));
    expect(distanceKm(tunisLat, tunisLon, tunisLat, tunisLon), 0);
    // Across the date line: Fiji to Samoa, not round the world.
    expect(distanceKm(-17.7134, 178.065, -13.759, -172.1046), closeTo(1140, 60));
  });
}
