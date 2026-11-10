import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/prayer/prayer_times.dart';
import 'package:rafiq/data/prayer_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

const tunis = Place(
  names: {'en': 'Tunis', 'ar': 'تونس'},
  countryCode: 'TN',
  latitude: 36.819,
  longitude: 10.166,
  fromLocation: false,
);

void main() {
  group('the settings', () {
    test('nothing set: no place, no times, no adhan', () {
      const s = PrayerSettings();
      expect(s.place, isNull);
      expect(s.timesOn(DateTime(2026, 11, 10)), isNull);
      expect(s.adhanOn, isFalse);
      for (final p in Prayer.values) {
        expect(s.alertOf(p), AdhanAlert.off);
      }
    });

    test('the method and the Asr follow the place until the user chooses', () {
      final s = const PrayerSettings().withPlace(tunis);
      expect(s.effectiveMethod, PrayerMethod.tunisia);
      expect(s.effectiveAsr, AsrSchool.standard);
      final chosen = s.withMethod(PrayerMethod.muslimWorldLeague).withAsr(AsrSchool.hanafi);
      expect(chosen.effectiveMethod, PrayerMethod.muslimWorldLeague);
      expect(chosen.effectiveAsr, AsrSchool.hanafi);
      expect(chosen.withMethod(null).effectiveMethod, PrayerMethod.tunisia, reason: 'automatic again');
    });

    test('the adhan on: each prayer sounds until told otherwise; the sunrise never', () {
      final s = const PrayerSettings().withPlace(tunis).withAdhan(on: true);
      expect([for (final p in Prayer.called) s.alertOf(p)], everyElement(AdhanAlert.sound));
      expect(s.alertOf(Prayer.sunrise), AdhanAlert.off);
      final quietFajr = s.withAlert(Prayer.fajr, AdhanAlert.vibrate).withAlert(Prayer.dhuhr, AdhanAlert.off);
      expect(quietFajr.alertOf(Prayer.fajr), AdhanAlert.vibrate);
      expect(quietFajr.alertOf(Prayer.dhuhr), AdhanAlert.off);
      expect(quietFajr.alertOf(Prayer.asr), AdhanAlert.sound);
      expect(quietFajr.withAdhan(on: false).alertOf(Prayer.fajr), AdhanAlert.off, reason: 'the whole adhan off');
      expect(quietFajr.withAdhan(on: false).withAdhan(on: true).alertOf(Prayer.fajr), AdhanAlert.vibrate,
          reason: 'each choice is kept');
    });

    test('minutes for the mosque: kept within half an hour, zero forgotten', () {
      final s = const PrayerSettings().withPlace(tunis).withOffset(Prayer.fajr, 2).withOffset(Prayer.isha, -99);
      expect(s.offsetOf(Prayer.fajr), 2);
      expect(s.offsetOf(Prayer.isha), -maxPrayerOffset);
      expect(s.offsetOf(Prayer.asr), 0);
      expect(s.withOffset(Prayer.fajr, 0).offsets.containsKey(Prayer.fajr), isFalse);
      final plain = const PrayerSettings().withPlace(tunis).timesOn(DateTime(2026, 11, 10))!;
      expect(s.timesOn(DateTime(2026, 11, 10))!.at(Prayer.fajr), plain.at(Prayer.fajr).add(const Duration(minutes: 2)));
    });

    test('the times of a day are those of its calendar date, whatever the hour', () {
      final s = const PrayerSettings().withPlace(tunis);
      expect(
        s.timesOn(DateTime(2026, 11, 10, 23, 59))!.at(Prayer.fajr),
        s.timesOn(DateTime(2026, 11, 10))!.at(Prayer.fajr),
      );
    });
  });

  group('the record', () {
    final full = const PrayerSettings()
        .withPlace(tunis)
        .withMethod(PrayerMethod.algeria)
        .withAsr(AsrSchool.hanafi)
        .withOffset(Prayer.maghrib, 3)
        .withAdhan(on: true)
        .withAlert(Prayer.fajr, AdhanAlert.silent)
        .withSound(AdhanSound.takbir);

    test('written and read back, the same', () {
      final back = PrayerSettings.fromJson(jsonDecode(jsonEncode(full.toJson())))!;
      expect(back.place, tunis);
      expect(back.method, PrayerMethod.algeria);
      expect(back.asr, AsrSchool.hanafi);
      expect(back.offsets, {Prayer.maghrib: 3});
      expect(back.adhanOn, isTrue);
      expect(back.alerts, {Prayer.fajr: AdhanAlert.silent});
      expect(back.sound, AdhanSound.takbir);
    });

    test('a part a later version wrote falls back to its default; the rest stands', () {
      final json = full.toJson()
        ..['method'] = 'mars'
        ..['sound'] = 'bells'
        ..['alerts'] = {'fajr': 'shout', 'asr': 'vibrate', 'sunrise': 'sound', 'noon': 'sound'}
        ..['offsets'] = {'fajr': 500, 'asr': 'two'};
      final back = PrayerSettings.fromJson(jsonDecode(jsonEncode(json)))!;
      expect(back.place, tunis);
      expect(back.method, isNull);
      expect(back.effectiveMethod, PrayerMethod.tunisia);
      expect(back.sound, AdhanSound.full);
      expect(back.alerts, {Prayer.asr: AdhanAlert.vibrate}, reason: 'no adhan for the sunrise');
      expect(back.offsets, {Prayer.fajr: maxPrayerOffset});
    });

    test('a place that is nowhere is no place', () {
      expect(
          Place.fromJson({
            'names': {'en': 'X'},
            'lat': 91,
            'lon': 0
          }),
          isNull);
      expect(Place.fromJson({'names': {}, 'lat': 1, 'lon': 1}), isNull);
      expect(
          Place.fromJson({
            'names': {'en': 'X'},
            'lat': '1',
            'lon': 1
          }),
          isNull);
      expect(Place.fromJson('Tunis'), isNull);
      final sea = Place.fromJson({
        'names': {'en': '0.00, 0.00'},
        'lat': 0,
        'lon': 0,
        'located': true
      })!;
      expect(sea.countryCode, isNull);
      expect(sea.fromLocation, isTrue);
      expect(sea.name('ar'), '0.00, 0.00', reason: 'the name it has, in any language');
    });

    test('not a version 1 record: not read', () {
      expect(PrayerSettings.fromJson({'v': 2}), isNull);
      expect(PrayerSettings.fromJson([]), isNull);
    });
  });

  group('the store', () {
    Future<SharedPreferences> prefs(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return SharedPreferences.getInstance();
    }

    test('nothing saved: the defaults', () async {
      final store = PrayerSettingsStore(await prefs({}));
      expect(store.load().place, isNull);
    });

    test('saved, then loaded', () async {
      final p = await prefs({});
      expect(await PrayerSettingsStore(p).save(const PrayerSettings().withPlace(tunis).withAdhan(on: true)), isTrue);
      final back = PrayerSettingsStore(p).load();
      expect(back.place, tunis);
      expect(back.adhanOn, isTrue);
    });

    test('an unreadable record is copied aside before anything is written over it', () async {
      for (final Object raw in ['{not json', '{"v":7}', 42]) {
        final p = await prefs({PrayerSettingsStore.key: raw});
        final store = PrayerSettingsStore(p);
        expect(store.load().place, isNull);
        expect(await store.save(const PrayerSettings().withPlace(tunis)), isTrue);
        final aside = p.getKeys().where((k) => k.startsWith('${PrayerSettingsStore.key}.unreadable.')).toList();
        expect(aside, hasLength(1), reason: '$raw');
        expect(p.getString(aside.single), '$raw');
        expect(PrayerSettingsStore(p).load().place, tunis);
      }
    });
  });
}
