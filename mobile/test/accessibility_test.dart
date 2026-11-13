/// Flutter's accessibility guidelines on every main screen, in both themes:
/// tap targets (48 dp Android, 44 dp iOS), a label on every tap target, and
/// text contrast. Large system text is covered by the small-phone tests.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/core/prayer/prayer_times.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/data/prayer_settings.dart';
import 'package:rafiq/features/adhkar/adhkar_screen.dart';
import 'package:rafiq/features/progress/progress_screen.dart';
import 'package:rafiq/services/location.dart';

import 'support/fakes.dart';
import 'support/app_nav.dart';

void main() {
  late Harness h;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> launch(WidgetTester tester, Map<String, Object> prefs) async {
    h = await Harness.create(prefs: {'taraweeh_intro_seen': true, ...prefs});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await settle(tester);
  }

  /// Prayer times for Tunis, the adhan on: Fajr on vibration, Asr off, and
  /// Fajr moved two minutes for the mosque.
  final prayerPrefs = {
    PrayerSettingsStore.key: jsonEncode(const PrayerSettings()
        .withPlace(loadCities().located(36.8065, 10.1815))
        .withAdhan(on: true)
        .withAlert(Prayer.fajr, AdhanAlert.vibrate)
        .withAlert(Prayer.asr, AdhanAlert.off)
        .withOffset(Prayer.fajr, 2)
        .toJson()),
  };

  /// The Reading screen's own (vertical) list: the year grid scrolls too.
  final readingList = find.descendant(of: find.byType(ProgressScreen), matching: find.byType(Scrollable)).first;

  Future<void> meetsGuidelines(WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  }

  for (final theme in ['light', 'dark']) {
    group('$theme theme', () {
      testWidgets('reader, scroll', (tester) async {
        await launch(tester, {'theme_mode': theme, 'daily_goal_pages': 20});
        await meetsGuidelines(tester);
      });

      testWidgets('reader, pages', (tester) async {
        await launch(tester, {'theme_mode': theme, 'reading_layout': 'pages'});
        await meetsGuidelines(tester);
      });

      testWidgets('Go to and search', (tester) async {
        await launch(tester, {'theme_mode': theme});
        await tapNav(tester, 'Surahs');
        await meetsGuidelines(tester);
        await tapNav(tester, 'Bookmarks');
        await meetsGuidelines(tester);
        await tapNav(tester, 'More');
        await meetsGuidelines(tester);
        await tapNav(tester, 'Read');
        await tester.tap(find.byTooltip('Search the Quran'));
        await settle(tester);
        await tester.enterText(find.byType(TextField), 'الحي القيوم');
        await settle(tester);
        await meetsGuidelines(tester);
      });

      testWidgets('khatm planner, before and during a plan', (tester) async {
        await launch(tester, {'theme_mode': theme});
        await tapNav(tester, 'More');
        await tester.tap(find.text('Khatm planner'));
        await settle(tester);
        await meetsGuidelines(tester);
        await tester.ensureVisible(find.text('Start khatm'));
        await settle(tester);
        await tester.tap(find.text('Start khatm'));
        await settle(tester);
        expect(find.text('0 of 604 pages read'), findsOneWidget);
        await meetsGuidelines(tester);
        await tester.ensureVisible(find.bySemanticsLabel('Juz 30, 0 of 23 pages read'));
        await settle(tester);
        await tester.tap(find.bySemanticsLabel('Juz 30, 0 of 23 pages read'));
        await settle(tester);
        expect(find.text('Mark all read'), findsOneWidget);
        await meetsGuidelines(tester); // the juz's pages
        await tester.tapAt(const Offset(20, 20)); // close the sheet
        await settle(tester);
        await tester.pageBack();
        await settle(tester);
        await tapNav(tester, 'Bookmarks');
        await meetsGuidelines(tester);
      });

      testWidgets('notes: the sheet and the Notes view', (tester) async {
        await launch(tester, {'theme_mode': theme});
        tester.widget<AyahBlock>(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == 2)).onTap!();
        await settle(tester);
        await tester.tap(find.text('Add a note'));
        await settle(tester);
        await tester.enterText(find.byType(TextField), 'A note on the second ayah');
        await settle(tester);
        await meetsGuidelines(tester);
        await tester.tap(find.text('Save'));
        await settle(tester);
        await tapNav(tester, 'Bookmarks');
        await tester.tap(find.text('Notes'));
        await settle(tester);
        expect(find.text('A note on the second ayah'), findsOneWidget);
        await meetsGuidelines(tester);
      });

      testWidgets('translation and tafsir', (tester) async {
        await launch(tester, {'theme_mode': theme});
        tester.widget<AyahBlock>(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == 2)).onTap!();
        await settle(tester);
        await meetsGuidelines(tester); // the ayah sheet, Translation and Tafsir live
        await tester.ensureVisible(find.text('Translation'));
        await settle(tester);
        await tester.tap(find.text('Translation'));
        await settle(tester);
        expect(find.textContaining('QuranEnc.com'), findsOneWidget);
        await meetsGuidelines(tester);
        await tester.tap(find.text('Tafsir'));
        await settle(tester);
        await meetsGuidelines(tester);
        await tester.tap(find.byTooltip('Choose the text'));
        await settle(tester);
        await meetsGuidelines(tester);
      });

      testWidgets('the reading chart and the daily reminder', (tester) async {
        await launch(tester, {
          'theme_mode': theme,
          'daily_goal_pages': 5,
          'reminder_on': true,
          'reading_log.v1': '{"v":1,"days":{"2026-11-02":[1,2,3],"2026-11-03":[4,5,6,7,8,9]}}',
        });
        await tapNav(tester, 'Bookmarks');
        await meetsGuidelines(tester); // the card
        await tester.tap(find.text('Your reading'));
        await settle(tester);
        await meetsGuidelines(tester);
        await tester.scrollUntilVisible(find.text('Reminder time'), 200, scrollable: readingList);
        await settle(tester);
        await meetsGuidelines(tester);
      });

      testWidgets('the reminder, offered after the first counted reading', (tester) async {
        await launch(tester, {
          'theme_mode': theme,
          'reading_pending.v1': '{"v":1,"days":{"2026-11-03":[40,41]}}',
        });
        await tester.tap(find.text('Count 2 pages'));
        await settle(tester);
        expect(find.text('A daily reminder?'), findsOneWidget);
        await meetsGuidelines(tester);
      });

      testWidgets('reviewing the last session', (tester) async {
        await launch(tester, {
          'theme_mode': theme,
          'reading_pending.v1': '{"v":1,"days":{"2026-11-03":[40,41],"2026-11-04":[42,43,44]}}',
        });
        expect(find.text('Count this reading?'), findsOneWidget);
        await meetsGuidelines(tester);
      });

      testWidgets('settings', (tester) async {
        await launch(tester, {'theme_mode': theme});
        await openSettings(tester);
        await meetsGuidelines(tester);
      });

      testWidgets('adhkar: the collections, and counting', (tester) async {
        await launch(tester, {
          'theme_mode': theme,
          'adhkar_day.v1': '{"v":1,"day":"2026-11-04","counts":{"prayer/pr01":1,"prayer/pr04":5}}',
        });
        await tapNav(tester, 'More');
        await tester.tap(find.text('Adhkar'));
        await settle(tester);
        await meetsGuidelines(tester);
        await tester.tap(find.text('After prayer'));
        await settle(tester);
        await meetsGuidelines(tester); // a card done, one under way
      });

      testWidgets('dhikr reminders: the setting and how often', (tester) async {
        await launch(tester, {'theme_mode': theme, 'dhikr_reminders_on': true});
        await tapNav(tester, 'More');
        await tester.tap(find.text('Adhkar'));
        await settle(tester);
        await tester.ensureVisible(find.text('How often'));
        await settle(tester);
        await meetsGuidelines(tester);
        await tester.tap(find.text('How often'));
        await settle(tester);
        expect(find.text('Every 4 hours'), findsOneWidget);
        await meetsGuidelines(tester);
      });

      testWidgets('prayer times: before a place, and choosing one', (tester) async {
        await launch(tester, {'theme_mode': theme});
        await tapNav(tester, 'More');
        await tester.tap(find.text('Prayer times'));
        await settle(tester);
        expect(find.text('Prayer times where you are'), findsOneWidget);
        await meetsGuidelines(tester);
        h.location.result = const LocationResult.failed(LocationFailure.deniedForever);
        await tester.tap(find.text('Use my location'));
        await settle(tester);
        expect(find.text('Open settings'), findsOneWidget);
        await meetsGuidelines(tester); // the notice and its action
        await tester.tap(find.text('Choose a city'));
        await settle(tester);
        await meetsGuidelines(tester);
        await tester.enterText(find.byType(TextField), 'tun');
        await settle(tester);
        expect(find.text('Tunis'), findsOneWidget);
        await meetsGuidelines(tester); // the towns found
      });

      testWidgets('prayer times and the adhan: the day, an alert, the method, adjusting', (tester) async {
        await launch(tester, {'theme_mode': theme, ...prayerPrefs});
        h.reminders.exact = false; // the notice about late adhans shows
        await tapNav(tester, 'More');
        await meetsGuidelines(tester); // "Next: ..." on the row
        await tester.tap(find.text('Prayer times'));
        await settle(tester);
        expect(find.text('NEXT PRAYER'), findsOneWidget);
        await meetsGuidelines(tester);
        await tester.tap(find.text('Isha'));
        await settle(tester);
        expect(find.text('Adhan for Isha'), findsOneWidget);
        await meetsGuidelines(tester);
        await tester.tapAt(const Offset(20, 20)); // close the sheet
        await settle(tester);
        await tester.scrollUntilVisible(find.text('Adjust the times'), 200, scrollable: find.byType(Scrollable).first);
        await settle(tester);
        expect(find.text('The adhan may come late'), findsOneWidget);
        await meetsGuidelines(tester); // the notice, the recording, the calculation
        await tester.tap(find.text('Method'));
        await settle(tester);
        expect(find.text('Automatic: Tunisia'), findsOneWidget);
        await meetsGuidelines(tester);
        await tester.tapAt(const Offset(20, 20));
        await settle(tester);
        await tester.tap(find.text('Adjust the times'));
        await settle(tester);
        expect(find.text('+2 min'), findsOneWidget);
        await meetsGuidelines(tester);
      });

      testWidgets('Taraweeh mode, following', (tester) async {
        await launch(tester, {'theme_mode': theme, 'dark_during_taraweeh': theme == 'dark'});
        await tester.tap(find.byIcon(Icons.mic_none));
        await settle(tester);
        h.engine.emit(const EngineReady());
        h.engine.emit(heard(at(93, 3)));
        await settle(tester);
        await meetsGuidelines(tester);
      });

      testWidgets('Taraweeh mode, repeated words: the choices', (tester) async {
        await launch(tester, {'theme_mode': theme, 'dark_during_taraweeh': theme == 'dark'});
        await tester.tap(find.byIcon(Icons.mic_none));
        await settle(tester);
        h.engine.emit(const EngineReady());
        h.engine.emit(heard(tie([(3, 50), (26, 108), (26, 110), (43, 63)])));
        await settle(tester);
        await meetsGuidelines(tester);
        h.engine.emit(heard(at(93, 3)));
        h.engine.emit(heard(tie([(18, 89), (18, 92)], position: pos(93, 3))));
        await settle(tester);
        await meetsGuidelines(tester);
      });
    });
  }

  testWidgets('200% system text: the review and the juz sheets', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, {'reading_pending.v1': '{"v":1,"days":{"2026-11-03":[40,41],"2026-11-04":[42,43,44]}}'});
    expect(find.text('Count this reading?'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'review sheet');
    await tester.ensureVisible(find.text('Not now'));
    await settle(tester);
    await tester.tap(find.text('Not now'));
    await settle(tester);
    await tapNav(tester, 'More');
    await tester.ensureVisible(find.text('Khatm planner'));
    await settle(tester);
    await tester.tap(find.text('Khatm planner'));
    await settle(tester);
    await tester.ensureVisible(find.text('Start khatm'));
    await settle(tester);
    await tester.tap(find.text('Start khatm'));
    await settle(tester);
    await tester.ensureVisible(find.bySemanticsLabel('Juz 1, 0 of 21 pages read'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'page map');
    await tester.tap(find.bySemanticsLabel('Juz 1, 0 of 21 pages read'));
    await settle(tester);
    expect(find.text('Mark all read'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'juz sheet');
  });

  testWidgets('200% system text: the adhkar and a long dhikr', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, {});
    await tapNav(tester, 'More');
    await tester.tap(find.text('Adhkar'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'adhkar screen');
    await tester.ensureVisible(find.text('Before sleep'));
    await settle(tester);
    await tester.tap(find.text('Before sleep'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'the three Quls');
    await tester.scrollUntilVisible(find.byWidgetPredicate((w) => w is DhikrCard && w.dhikr.id == 'sl11'), 400,
        scrollable: find.byType(Scrollable).first);
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'a long dhikr, its meaning and a three-digit counter');
  });

  testWidgets('200% system text: dhikr reminders and how often', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, {'dhikr_reminders_on': true});
    await tapNav(tester, 'More');
    await tester.tap(find.text('Adhkar'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('How often'), 200, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'the setting');
    await tester.tap(find.text('How often'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'the sheet');
  });

  testWidgets('200% system text: prayer times, from no place to the adhan and its sheets', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, {});
    await tapNav(tester, 'More');
    await tester.tap(find.text('Prayer times'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'the intro');
    h.location.result = const LocationResult.failed(LocationFailure.serviceOff);
    await tester.scrollUntilVisible(find.text('Use my location'), 200, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.tap(find.text('Use my location'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'the intro, location off');
    await tester.scrollUntilVisible(find.text('Open settings'), 200, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'the notice');
    await tester.ensureVisible(find.text('Choose a city'));
    await settle(tester);
    await tester.tap(find.text('Choose a city'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'the place screen');
    await tester.enterText(find.byType(TextField), 'saint');
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'towns with long names');
    await tester.enterText(find.byType(TextField), 'tunis');
    await settle(tester);
    await tester.tap(find.text('Tunis'));
    await settle(tester);
    expect(find.text('NEXT PRAYER'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the day');
    h.reminders.exact = false;
    h.reminders.grantExact = false;
    await tester.scrollUntilVisible(find.text('Adhan'), 200, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    await tester.tap(find.text('Adhan'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'why alarms are asked for');
    await tester.ensureVisible(find.text('Continue'));
    await settle(tester);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'the adhan on, with its icons');
    await tester.scrollUntilVisible(find.text('Adjust the times'), 200, scrollable: find.byType(Scrollable).first);
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'the late notice and the calculation');
    await tester.tap(find.text('Adjust the times'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'adjusting');
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    await tester.ensureVisible(find.text('Method'));
    await settle(tester);
    await tester.tap(find.text('Method'));
    await settle(tester);
    expect(find.text('Automatic: Tunisia'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the methods');
  });

  testWidgets('200% system text: the study view and its source sheet', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, {});
    tester.widget<AyahBlock>(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == 2)).onTap!();
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'ayah sheet');
    await tester.ensureVisible(find.text('Tafsir'));
    await settle(tester);
    await tester.tap(find.text('Tafsir'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'study view, tafsir');
    await tester.tap(find.text('Translation'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'study view, translation');
    await tester.tap(find.byTooltip('Choose the text'));
    await settle(tester);
    expect(find.text('Choose a translation'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'source sheet');
  });

  testWidgets('200% system text: the reading card and screen, and the reminder offer', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, {
      'daily_goal_pages': 20,
      'reminder_on': true,
      'reading_log.v1': '{"v":1,"days":{"2026-11-02":[1,2,3],"2026-11-03":[4,5,6,7,8,9]}}',
      'reading_pending.v1': '{"v":1,"days":{"2026-11-04":[40,41]}}',
    });
    await tester.ensureVisible(find.text('Not now'));
    await settle(tester);
    await tester.tap(find.text('Not now'));
    await settle(tester);
    await tapNav(tester, 'Bookmarks');
    expect(tester.takeException(), isNull, reason: 'reading card');
    await tester.tap(find.text('Your reading'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'reading screen');
    await tester.scrollUntilVisible(find.text('Reminder time'), 200, scrollable: readingList);
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'reading screen, reminder');
  });

  testWidgets('200% system text: every main screen lays out without overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, {'daily_goal_pages': 20});
    expect(tester.takeException(), isNull, reason: 'reader');
    for (final tab in ['Surahs', 'Bookmarks', 'More', 'Read']) {
      await tapNav(tester, tab);
      expect(tester.takeException(), isNull, reason: tab);
    }
    tester.widget<AyahBlock>(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == 2)).onTap!();
    await settle(tester);
    await tester.ensureVisible(find.text('Add a note'));
    await settle(tester);
    await tester.tap(find.text('Add a note'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'note sheet');
    await tester.enterText(find.byType(TextField), 'A note at 200%');
    await settle(tester);
    await tester.ensureVisible(find.text('Save'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);
    await tapNav(tester, 'Bookmarks');
    await tester.tap(find.text('Notes'));
    await settle(tester);
    expect(find.text('A note at 200%'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Notes view');
    await tapNav(tester, 'Read');
    await tester.tap(find.byTooltip('Search the Quran'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'search');
    await tester.pageBack();
    await settle(tester);
    await openSettings(tester);
    expect(tester.takeException(), isNull, reason: 'settings');
    await tester.pageBack();
    await settle(tester);
    await tapNav(tester, 'More');
    await tester.ensureVisible(find.text('Khatm planner'));
    await settle(tester);
    await tester.tap(find.text('Khatm planner'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'khatm planner, no plan');
    await tester.ensureVisible(find.text('Start khatm'));
    await settle(tester);
    await tester.tap(find.text('Start khatm'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'khatm planner, a plan');
    expect(find.text('0 of 604 pages read'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    await tapNav(tester, 'Read');
    await tester.tap(find.byIcon(Icons.mic_none));
    await settle(tester);
    h.engine.emit(const EngineReady());
    h.engine.emit(heard(at(2, 282)));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'Taraweeh mode');
  });
}
