import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/core/prayer/prayer_times.dart';
import 'package:rafiq/data/prayer_settings.dart';
import 'package:rafiq/features/prayer/adhan_sync.dart';
import 'package:rafiq/features/prayer/prayer_controller.dart';
import 'package:rafiq/features/prayer/prayer_screen.dart';
import 'package:rafiq/l10n/l10n.dart';
import 'package:rafiq/services/location.dart';
import 'package:rafiq/services/reminders.dart';

import '../support/app_nav.dart';
import '../support/fakes.dart';

/// Tunis, as the phone's location finds it (to two decimals).
final tunis = loadCities().located(36.8065, 10.1815);

String saved(PrayerSettings settings) => jsonEncode(settings.toJson());

final withTunis = const PrayerSettings().withPlace(tunis);

/// Tuesday 10 November 2026, half past nine in Tunis. That day there:
/// Fajr 5:23, sunrise 6:52, Dhuhr 12:03, Asr 14:52, Maghrib 17:14, Isha 18:43.
final morning = DateTime(2026, 11, 10, 9, 30);

void main() {
  group('the next prayer', () {
    final l = lookupAppLocalizations(const Locale('en'));

    test('in the morning: Dhuhr, today', () {
      final table = prayerTimetable(withTunis, morning, tunisClock)!;
      expect(table.today.map((m) => m.prayer), Prayer.values);
      expect(table.today.map((m) => m.at), [
        DateTime(2026, 11, 10, 5, 23),
        DateTime(2026, 11, 10, 6, 52),
        DateTime(2026, 11, 10, 12, 3),
        DateTime(2026, 11, 10, 14, 52),
        DateTime(2026, 11, 10, 17, 14),
        DateTime(2026, 11, 10, 18, 43),
      ]);
      expect(table.next, (prayer: Prayer.dhuhr, at: DateTime(2026, 11, 10, 12, 3)));
      expect(countdownLabel(l, morning, table.next!.at), 'in 2 h 33 min');
    });

    test('before the sunrise: Dhuhr, not the sunrise', () {
      final table = prayerTimetable(withTunis, DateTime(2026, 11, 10, 6), tunisClock)!;
      expect(table.next!.prayer, Prayer.dhuhr);
    });

    test('at a prayer\'s minute it is no longer next; after Isha, tomorrow\'s Fajr', () {
      expect(prayerTimetable(withTunis, DateTime(2026, 11, 10, 12, 3), tunisClock)!.next!.prayer, Prayer.asr);
      final night = prayerTimetable(withTunis, DateTime(2026, 11, 10, 22), tunisClock)!;
      expect(night.next!.prayer, Prayer.fajr);
      expect(night.next!.at.day, 11);
      expect(countdownLabel(l, DateTime(2026, 11, 10, 22), night.next!.at), startsWith('in 7 h'));
    });

    test('no place: no timetable', () {
      expect(prayerTimetable(const PrayerSettings(), morning, tunisClock), isNull);
    });

    test('how long until: to the minute, rounded up', () {
      final at = DateTime(2026, 11, 10, 12, 3);
      expect(countdownLabel(l, DateTime(2026, 11, 10, 11, 51), at), 'in 12 min');
      expect(countdownLabel(l, DateTime(2026, 11, 10, 11, 3), at), 'in 1 h');
      expect(countdownLabel(l, DateTime(2026, 11, 10, 12, 2, 30), at), 'in 1 min');
      expect(countdownLabel(l, at, at), 'now');
      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(countdownLabel(ar, morning, at), 'بعد 2 س 33 د');
    });

    test('minutes for the mosque, signed', () {
      expect(offsetLabel(l, 0), 'As computed');
      expect(offsetLabel(l, 2), '+2 min');
      expect(offsetLabel(l, -3), '−3 min');
    });
  });

  group('ids', () {
    test('each prayer of each day of the month has its own slot, and keeps it', () {
      final slots = <int>{};
      for (var d = 0; d < adhanDays; d++) {
        final day = DateTime(2026, 11, 10 + d);
        for (var i = 0; i < adhanSlotsPerDay; i++) {
          final slot = adhanSlot(day.year, day.month, day.day, i);
          expect(slots.add(slot), isTrue);
          expect(adhanIdBase + slot, lessThan(adhanTestId), reason: 'below the test\'s id');
        }
      }
      expect(adhanSlot(2026, 11, 10, 2), adhanSlot(2026, 11, 10, 2));
      expect(adhanSlotDays, greaterThan(adhanDays));
    });

    test('an adhan is told from a dhikr by its payload', () {
      expect(isAdhanPayload('prayer'), isTrue);
      expect(isAdhanPayload('prayer|adhan_full|exact'), isTrue);
      expect(isAdhanPayload(dhikrPayload), isFalse);
      expect(isAdhanPayload('prayers'), isFalse);
    });
  });

  group('the screen', () {
    late Harness h;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> launch(WidgetTester tester, {PrayerSettings? settings, DateTime? now, String? language}) async {
      h = await Harness.create(prefs: {
        'taraweeh_intro_seen': true,
        if (settings != null) PrayerSettingsStore.key: saved(settings),
        if (language != null) 'language': language,
      });
      h.now = now ?? morning;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
      await settle(tester);
    }

    Future<void> openPrayer(WidgetTester tester) async {
      await tapNav(tester, 'More');
      await tester.tap(find.text('Prayer times'));
      await settle(tester);
    }

    Future<void> reveal(WidgetTester tester, String text) async {
      await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
      await settle(tester);
    }

    PrayerSettings stored() => PrayerSettings.fromJson(jsonDecode(h.prefs.getString(PrayerSettingsStore.key)!))!;

    /// The adhans scheduled for [prayer].
    List<Reminder> adhansOf(Prayer prayer) => [
          for (final r in h.reminders.adhan)
            if (r.slot % adhanSlotsPerDay == prayer.index) r
        ];

    testWidgets('no place yet: what it is for; my location gives Tunis and its times', (tester) async {
      await launch(tester);
      await tapNav(tester, 'More');
      expect(find.text('For where you are, with the adhan'), findsOneWidget);
      await tester.tap(find.text('Prayer times'));
      await settle(tester);
      expect(find.text('Prayer times where you are'), findsOneWidget);
      expect(h.location.located, 0, reason: 'nothing is asked before the user asks');
      await tester.tap(find.text('Use my location'));
      await settle(tester);
      expect(h.location.located, 1);
      expect(find.text('NEXT PRAYER'), findsOneWidget);
      expect(find.text('Dhuhr'), findsNWidgets(2), reason: 'the next prayer, and its row');
      expect(find.text('12:03 PM · in 2 h 33 min'), findsOneWidget);
      for (final time in ['5:23 AM', '6:52 AM', '12:03 PM', '2:52 PM', '5:14 PM', '6:43 PM']) {
        expect(find.text(time), findsOneWidget);
      }
      expect(find.text('TUESDAY, NOVEMBER 10'), findsOneWidget);
      await reveal(tester, 'Method');
      expect(find.text('Tunis, Tunisia'), findsOneWidget);
      expect(find.text('From your location'), findsOneWidget);
      expect(find.text('Tunisia'), findsOneWidget, reason: 'the method of the place\'s country');
      final place = stored().place!;
      expect((place.latitude, place.longitude), (36.81, 10.18), reason: 'kept to about a kilometre');
      expect(place.fromLocation, isTrue);
      expect(h.reminders.adhanReplaced, 0, reason: 'the adhan is off until turned on');
    });

    testWidgets('location refused: says so, and a city can be chosen instead', (tester) async {
      await launch(tester);
      h.location.result = const LocationResult.failed(LocationFailure.denied);
      await openPrayer(tester);
      await tester.tap(find.text('Use my location'));
      await settle(tester);
      expect(find.text('Location is not allowed for Rafiq. You can choose a city instead.'), findsOneWidget);
      expect(find.text('Open settings'), findsNothing, reason: 'asking again is still possible');
      expect(h.prefs.getString(PrayerSettingsStore.key), isNull);

      h.location.result = const LocationResult.failed(LocationFailure.deniedForever);
      await tester.tap(find.text('Use my location'));
      await settle(tester);
      await tester.tap(find.text('Open settings'));
      expect(h.location.settingsOpened, [LocationFailure.deniedForever]);

      h.location.result = const LocationResult.failed(LocationFailure.serviceOff);
      await tester.tap(find.text('Use my location'));
      await settle(tester);
      expect(find.textContaining('Location is turned off on this phone'), findsOneWidget);

      h.location.result = const LocationResult.failed(LocationFailure.unavailable);
      await tester.tap(find.text('Use my location'));
      await settle(tester);
      expect(find.textContaining('could not be found'), findsOneWidget);
      expect(find.text('Open settings'), findsNothing);
    });

    testWidgets('a city chosen by name: its times, and it is not "my location"', (tester) async {
      await launch(tester);
      await openPrayer(tester);
      await tester.tap(find.text('Choose a city'));
      await settle(tester);
      expect(find.text('Use my location'), findsOneWidget, reason: 'still offered beside the search');
      await tester.enterText(find.byType(TextField), 'qayrawan');
      await settle(tester);
      expect(find.textContaining('No city found for “qayrawan”'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'kairou');
      await settle(tester);
      expect(find.text('Tunisia'), findsWidgets, reason: 'each town with its country');
      await tester.tap(find.text('Kairouan'));
      await settle(tester);
      expect(find.byType(PrayerScreen), findsOneWidget);
      expect(find.text('NEXT PRAYER'), findsOneWidget);
      await reveal(tester, 'Method');
      expect(find.text('Kairouan, Tunisia'), findsOneWidget);
      expect(find.text('From your location'), findsNothing);
      expect(stored().place!.fromLocation, isFalse);
      expect(h.location.located, 0, reason: 'no location was asked for');

      // Changed from the screen: the phone's location this time.
      await tester.tap(find.text('Place'));
      await settle(tester);
      await tester.tap(find.text('Use my location'));
      await settle(tester);
      await reveal(tester, 'Method');
      expect(find.text('Tunis, Tunisia'), findsOneWidget);
    });

    testWidgets('More says the next prayer once a place is known', (tester) async {
      await launch(tester, settings: withTunis);
      await tapNav(tester, 'More');
      expect(find.text('Next: Dhuhr, 12:03 PM'), findsOneWidget);
    });

    testWidgets('the adhan turned on: permission, then a month of adhans, each on its minute', (tester) async {
      await launch(tester, settings: withTunis);
      expect(h.reminders.adhanReplaced, 0);
      await openPrayer(tester);
      expect(find.text('The call to prayer at each prayer time, even when Rafiq is closed'), findsOneWidget);
      expect(find.text('Test the adhan'), findsNothing);
      await tester.tap(find.text('Adhan'));
      await settle(tester);
      expect(h.reminders.asked, 1);
      expect(h.reminders.exactAsked, 0, reason: 'already allowed: nothing more to ask');
      expect(find.text('Adhan on'), findsOneWidget);
      expect(stored().adhanOn, isTrue);

      final adhan = h.reminders.adhan;
      // Four left today, five a day for 29 more days, and the notice at the end.
      expect(adhan, hasLength(4 + 29 * 5 + 1));
      expect(adhan.first.at, DateTime(2026, 11, 10, 12, 3));
      expect(adhan.first.title, 'Dhuhr · 12:03 PM');
      expect(adhan.first.body, 'It is time to pray · Tunis');
      expect(adhan.first.tone!.sound, 'adhan_full');
      expect(adhan.first.tone!.channelId, 'adhan_full');
      expect(adhan.first.tone!.channelName, 'Adhan: the whole adhan');
      expect(adhan[1].at, DateTime(2026, 11, 10, 14, 52));
      expect(adhansOf(Prayer.sunrise), isEmpty, reason: 'the sunrise is not called');
      expect(adhansOf(Prayer.fajr), hasLength(29));
      expect(adhansOf(Prayer.fajr).first.at, DateTime(2026, 11, 11, 5, 24));
      expect({for (final r in adhan) r.slot}, hasLength(adhan.length), reason: 'an id each');
      for (var i = 1; i < adhan.length; i++) {
        expect(adhan[i].at.isAfter(adhan[i - 1].at), isTrue);
      }
      // After the last day's Isha: nobody opened Rafiq for a month.
      expect(adhan.last.title, 'Open Rafiq to keep the adhan');
      expect(adhan.last.tone!.isSilent, isTrue);
      expect(adhan.last.at.difference(adhan[adhan.length - 2].at), adhanRenewAfter);
      expect(adhan.last.at.day, 9, reason: '9 December, the thirtieth day');
      expect(h.reminders.scheduled, isEmpty, reason: 'the reading reminder is apart');
      expect(h.reminders.dhikr.isOff, isTrue);
    });

    testWidgets('each prayer its own way: vibration for Fajr, nothing for Asr', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true));
      expect(h.reminders.adhan, isNotEmpty, reason: 'scheduled when the app opens');
      await openPrayer(tester);
      // Each row is one item for a screen reader: its name, time and alert.
      expect(find.bySemanticsLabel(RegExp('Adhan: Adhan')), findsNWidgets(5));
      expect(find.bySemanticsLabel(RegExp(r'^Fajr\s5:23 AM\sAdhan: Adhan$')), findsOneWidget);
      await tester.tap(find.text('Fajr'));
      await settle(tester);
      expect(find.text('Adhan for Fajr'), findsOneWidget);
      await tester.tap(find.text('Vibration'));
      await settle(tester);
      expect(find.bySemanticsLabel(RegExp('Adhan: Vibration')), findsOneWidget);
      expect(stored().alerts, {Prayer.fajr: AdhanAlert.vibrate});
      for (final r in adhansOf(Prayer.fajr)) {
        expect(r.tone!.sound, isNull);
        expect(r.tone!.vibrate, isTrue);
        expect(r.tone!.channelId, 'adhan_vibrate');
      }
      expect(adhansOf(Prayer.dhuhr).first.tone!.sound, 'adhan_full', reason: 'the others as before');

      await tester.tap(find.text('Asr'));
      await settle(tester);
      await tester.tap(find.text('Off'));
      await settle(tester);
      expect(adhansOf(Prayer.asr), isEmpty);
      expect(h.reminders.adhan, hasLength(3 + 29 * 4 + 1));

      await tester.tap(find.text('Maghrib'));
      await settle(tester);
      await tester.tap(find.text('Silent notification'));
      await settle(tester);
      expect(adhansOf(Prayer.maghrib).every((r) => r.tone!.isSilent), isTrue);
      expect(adhansOf(Prayer.maghrib).first.tone!.channelId, 'adhan_silent');

      // The sunrise has no adhan to choose.
      await tester.tap(find.text('Sunrise'));
      await settle(tester);
      expect(find.textContaining('Adhan for'), findsNothing);
    });

    testWidgets('the takbir only, and a test of it', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true));
      await openPrayer(tester);
      await reveal(tester, 'Test the adhan');
      await tester.tap(find.text('Recording'));
      await settle(tester);
      await tester.tap(find.text('The opening takbir only'));
      await settle(tester);
      expect(stored().sound, AdhanSound.takbir);
      expect(h.reminders.adhan.first.tone!.sound, 'adhan_takbir');
      expect(h.reminders.adhan.first.tone!.channelName, 'Adhan: the takbir only');

      await tester.tap(find.text('Test the adhan'));
      await settle(tester);
      expect(h.reminders.shown, hasLength(1));
      expect(h.reminders.shown.single.title, 'Adhan test');
      expect(h.reminders.shown.single.tone!.sound, 'adhan_takbir');
    });

    testWidgets('alarms not allowed: asked once, then silent and said so; allowed, the adhan sounds', (tester) async {
      await launch(tester, settings: withTunis);
      h.reminders
        ..exact = false
        ..grantExact = false;
      await openPrayer(tester);
      await tester.tap(find.text('Adhan'));
      await settle(tester);
      expect(find.textContaining('allow Rafiq to set alarms and reminders'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(h.reminders.exactAsked, 1);
      expect(stored().adhanOn, isTrue, reason: 'on all the same: late is better than never');
      expect(h.reminders.adhan, hasLength(150));
      expect(h.reminders.adhan.every((r) => r.tone!.isSilent), isTrue, reason: 'no call to prayer an hour late');
      await reveal(tester, 'The adhan may come late');

      h.reminders.grantExact = true;
      await tester.tap(find.text('Allow alarms'));
      await settle(tester);
      expect(h.reminders.exactAsked, 2);
      expect(find.text('The adhan may come late'), findsNothing);
      expect(h.reminders.adhan.first.tone!.sound, 'adhan_full');
    });

    testWidgets('the permission taken back while the app was away: silent again when it is shown', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true));
      expect(h.reminders.adhan.first.tone!.sound, 'adhan_full');
      h.reminders.exact = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(h.reminders.adhan.every((r) => r.tone!.isSilent), isTrue);
    });

    testWidgets('notifications refused: stays off, says where to turn them on', (tester) async {
      await launch(tester, settings: withTunis);
      h.reminders.allow = false;
      await openPrayer(tester);
      await tester.tap(find.text('Adhan'));
      await settle(tester);
      expect(stored().adhanOn, isFalse);
      expect(h.reminders.adhan, isEmpty);
      expect(find.textContaining('Notifications are off for Rafiq'), findsOneWidget);
    });

    testWidgets('notifications turned off later: the screen says so', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true));
      h.reminders.allow = false;
      await openPrayer(tester);
      await reveal(tester, 'Notifications are off');
      expect(find.textContaining('Notifications are off for Rafiq'), findsOneWidget);
    });

    testWidgets('turned off: every adhan cancelled, the other reminders kept', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true));
      await h.prefs.setBool('dhikr_reminders_on', true);
      expect(h.reminders.adhan, isNotEmpty);
      await openPrayer(tester);
      await tester.tap(find.text('Adhan'));
      await settle(tester);
      expect(stored().adhanOn, isFalse);
      expect(h.reminders.adhan, isEmpty);
      expect(find.text('Test the adhan'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Adhan: Adhan')), findsNothing);
    });

    testWidgets('Taraweeh mode: no adhan sounds into the microphone for 3 hours', (tester) async {
      // 17:00: Maghrib (17:14) and Isha (18:43) fall within the three hours.
      await launch(tester, settings: withTunis.withAdhan(on: true), now: DateTime(2026, 11, 10, 17));
      expect(adhansOf(Prayer.maghrib).first.tone!.sound, 'adhan_full');
      await tester.tap(taraweehButton);
      await settle(tester);
      expect(adhansOf(Prayer.maghrib).first.tone!.isSilent, isTrue);
      expect(adhansOf(Prayer.isha).first.tone!.isSilent, isTrue);
      expect(adhansOf(Prayer.isha)[1].tone!.sound, 'adhan_full', reason: 'tomorrow as usual');
      expect(adhansOf(Prayer.fajr).first.tone!.sound, 'adhan_full');
      await tester.tap(find.byTooltip('Back to reading'));
      await settle(tester);
      expect(adhansOf(Prayer.maghrib).first.tone!.sound, 'adhan_full');
    });

    testWidgets('a tapped adhan opens the prayer times, once', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true));
      h.reminders.tap('prayer|adhan_full|exact');
      await settle(tester);
      expect(find.byType(PrayerScreen), findsOneWidget);
      h.reminders.tap('prayer');
      await settle(tester);
      expect(find.byType(PrayerScreen), findsOneWidget, reason: 'one screen, not two');
    });

    testWidgets('another method: the times and the adhans move', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true));
      await openPrayer(tester);
      await reveal(tester, 'Method');
      await tester.tap(find.text('Method'));
      await settle(tester);
      expect(find.text('Automatic: Tunisia'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('France (UOIF, 12°)'), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('France (UOIF, 12°)'));
      await settle(tester);
      expect(stored().method, PrayerMethod.france);
      expect(find.text('France (UOIF, 12°)'), findsOneWidget);
      // 12° below the horizon comes later than 18°: Fajr 5:54, not 5:24.
      expect(adhansOf(Prayer.fajr).first.at.isAfter(DateTime(2026, 11, 11, 5, 45)), isTrue);

      await tester.tap(find.text('Method'));
      await settle(tester);
      await tester.tap(find.text('Automatic: Tunisia'));
      await settle(tester);
      expect(stored().method, isNull);
      expect(adhansOf(Prayer.fajr).first.at, DateTime(2026, 11, 11, 5, 24));
    });

    testWidgets('the Hanafi Asr, and two minutes more for the mosque\'s Fajr', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true));
      await openPrayer(tester);
      await reveal(tester, 'Adjust the times');
      expect(find.text('Maliki, Shafi’i, Hanbali'), findsOneWidget);
      await tester.tap(find.text('Maliki, Shafi’i, Hanbali'));
      await settle(tester);
      await tester.tap(find.text('Hanafi (later)'));
      await settle(tester);
      expect(stored().asr, AsrSchool.hanafi);
      expect(adhansOf(Prayer.asr).first.at, DateTime(2026, 11, 10, 15, 34));

      expect(find.text('As computed'), findsOneWidget);
      await tester.tap(find.text('Adjust the times'));
      await settle(tester);
      await tester.tap(find.byTooltip('Fajr: one minute later'));
      await settle(tester);
      await tester.tap(find.byTooltip('Fajr: one minute later'));
      await settle(tester);
      expect(find.text('+2 min'), findsOneWidget);
      await tester.tap(find.byTooltip('Isha: one minute earlier'));
      await settle(tester);
      expect(find.text('−1 min'), findsOneWidget);
      expect(stored().offsets, {Prayer.fajr: 2, Prayer.isha: -1});
      expect(adhansOf(Prayer.fajr).first.at, DateTime(2026, 11, 11, 5, 26));
      expect(adhansOf(Prayer.isha).first.at, DateTime(2026, 11, 10, 18, 42));
      await tester.tapAt(const Offset(20, 20)); // close the sheet
      await settle(tester);
      expect(find.text('2 times adjusted'), findsOneWidget);
    });

    testWidgets('in Arabic: the screen and the notifications', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true), language: 'ar');
      expect(h.reminders.adhan.first.title, 'الظهر · 12:03 م');
      expect(h.reminders.adhan.first.body, 'حان وقت الصلاة · تونس');
      expect(h.reminders.adhan.first.tone!.channelName, 'الأذان: كاملًا');
      await tapNav(tester, 'المزيد');
      expect(find.text('التالية: الظهر، 12:03 م'), findsOneWidget);
      await tester.tap(find.text('مواقيت الصلاة'));
      await settle(tester);
      expect(find.text('الصلاة القادمة'), findsOneWidget);
      expect(find.text('12:03 م · بعد 2 س 33 د'), findsOneWidget);
      await reveal(tester, 'طريقة الحساب');
      expect(find.text('تونس، تونس'), findsNothing, reason: 'the town and the country share a name: said once');
      expect(find.text('تونس'), findsNWidgets(2), reason: 'the place, and the method');
    });

    testWidgets('in French: the country\'s name, and the hour as France writes it', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true), language: 'fr');
      expect(h.reminders.adhan.first.title, 'Dhuhr · 12:03');
      expect(h.reminders.adhan.first.body, 'C’est l’heure de la prière · Tunis');
      await tapNav(tester, 'Plus');
      await tester.tap(find.text('Heures de prière'));
      await settle(tester);
      await reveal(tester, 'Méthode');
      expect(find.text('Tunis, Tunisie'), findsOneWidget);
    });

    testWidgets('travelling: a place from the phone\'s location follows it to another town', (tester) async {
      h = await Harness.create(prefs: {
        'taraweeh_intro_seen': true,
        PrayerSettingsStore.key: saved(withTunis.withAdhan(on: true)),
      });
      h.now = morning;
      h.location.known = const LocationResult.found(34.7406, 10.7603); // Sfax, 235 km south
      await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
      await settle(tester);
      expect(h.location.located, 0, reason: 'the user is asked nothing');
      expect(stored().place!.name('en'), 'Sfax');
      expect(stored().place!.fromLocation, isTrue);
      expect(h.reminders.adhan.first.body, 'It is time to pray · Sfax');
      expect(h.reminders.adhan.first.at, DateTime(2026, 11, 10, 12, 1), reason: 'Sfax is a little further east');
    });

    testWidgets('travelling: across town changes nothing', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true));
      final before = h.reminders.adhanReplaced;
      h.location.known = const LocationResult.found(36.86, 10.33); // La Marsa, 15 km away
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(stored().place, tunis);
      expect(h.reminders.adhanReplaced, before);
    });

    testWidgets('travelling: a chosen place never moves', (tester) async {
      final kairouan = loadCities().chosen(loadCities().search('kairouan').first);
      await launch(tester, settings: const PrayerSettings().withPlace(kairouan));
      h.location.known = const LocationResult.found(34.7406, 10.7603);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(stored().place, kairouan);
    });

    testWidgets('the day moves on: opened the next morning, the month starts from there', (tester) async {
      await launch(tester, settings: withTunis.withAdhan(on: true));
      expect(h.reminders.adhan.first.at, DateTime(2026, 11, 10, 12, 3));
      final slot = adhansOf(Prayer.isha)[1].slot; // tomorrow's Isha
      h.now = DateTime(2026, 11, 11, 8);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(h.reminders.adhan.first.at, DateTime(2026, 11, 11, 12, 3));
      expect(h.reminders.adhan.last.at.day, 10, reason: '10 December now');
      expect(adhansOf(Prayer.isha).first.slot, slot, reason: 'the same prayer keeps its id');
    });

    testWidgets('a record that cannot be read: the intro again, and the record kept aside', (tester) async {
      h = await Harness.create(prefs: {'taraweeh_intro_seen': true, PrayerSettingsStore.key: '{"v":1,"place":'});
      h.now = morning;
      await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
      await settle(tester);
      await openPrayer(tester);
      expect(find.text('Prayer times where you are'), findsOneWidget);
      expect(h.prefs.getKeys().where((k) => k.startsWith('${PrayerSettingsStore.key}.unreadable.')), hasLength(1));
    });
  });
}
