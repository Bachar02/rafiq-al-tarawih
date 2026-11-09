import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/data/adhkar.dart';
import 'package:rafiq/features/adhkar/adhkar_controller.dart';
import 'package:rafiq/features/adhkar/adhkar_screen.dart';
import 'package:rafiq/features/study/study_screen.dart';

import '../support/app_nav.dart';
import '../support/fakes.dart';

void main() {
  late Harness h;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> launch(WidgetTester tester, [Map<String, Object> prefs = const {}, DateTime? now]) async {
    h = await Harness.create(prefs: {'taraweeh_intro_seen': true, ...prefs});
    if (now != null) h.now = now;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await settle(tester);
  }

  Future<void> openAdhkar(WidgetTester tester) async {
    await tapNav(tester, 'More');
    await tester.tap(find.text('Adhkar'));
    await settle(tester);
  }

  Future<void> openCollection(WidgetTester tester, String title) async {
    await openAdhkar(tester);
    await tester.tap(find.text(title));
    await settle(tester);
  }

  /// The card of a dhikr, by id (the list builds only the cards in view).
  Finder card(String id) => find.byWidgetPredicate((w) => w is DhikrCard && w.dhikr.id == id);

  Future<void> show(WidgetTester tester, String id) async {
    await tester.scrollUntilVisible(card(id), 300, scrollable: find.byType(Scrollable).first);
    await settle(tester);
  }

  /// Tap a dhikr's card near its top: inside the card, clear of the
  /// translation button, and on screen however tall the card.
  Future<void> tapCard(WidgetTester tester, String id) async {
    await show(tester, id);
    await tester.tapAt(tester.getRect(card(id)).topLeft + const Offset(40, 20));
    await settle(tester);
  }

  /// The counter of a dhikr: times left, or a check.
  Finder counter(String id, String left) => find.descendant(of: card(id), matching: find.text(left));
  Finder doneMark(String id) => find.descendant(of: card(id), matching: find.byIcon(Icons.check));

  /// What the progress bar (always in view) says.
  String? progress(WidgetTester tester) =>
      tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).semanticsLabel;

  Map<String, dynamic> saved() => jsonDecode(h.prefs.getString(AdhkarStore.key)!) as Map<String, dynamic>;

  group('the Adhkar screen', () {
    testWidgets('More leads to it, saying what this time of day calls for', (tester) async {
      await launch(tester); // 20:00
      await tapNav(tester, 'More');
      expect(find.text('Now: Evening adhkar'), findsOneWidget);
      await tester.tap(find.text('Adhkar'));
      await settle(tester);
      expect(find.byType(AdhkarScreen), findsOneWidget);
      for (final title in ['Morning adhkar', 'Evening adhkar', 'After prayer', 'Before sleep', 'Any time']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('After Fajr'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget, reason: 'one collection is suggested');
      final evening = find.ancestor(of: find.text('Evening adhkar'), matching: find.byType(InkWell));
      expect(find.descendant(of: evening, matching: find.text('Now')), findsOneWidget);
    });

    testWidgets('at midday nothing is suggested', (tester) async {
      await launch(tester, {}, DateTime(2026, 11, 4, 12, 30));
      await tapNav(tester, 'More');
      expect(find.text('Morning, evening, after prayer, before sleep'), findsOneWidget);
      expect(adhkarNow(DateTime(2026, 11, 4, 6)), AdhkarCollection.morning);
      expect(adhkarNow(DateTime(2026, 11, 4, 23)), AdhkarCollection.sleep);
      expect(adhkarNow(DateTime(2026, 11, 4, 1)), AdhkarCollection.sleep);
    });
  });

  group('counting', () {
    testWidgets('a dhikr said once: one tap, a check, the progress moves and is saved', (tester) async {
      await launch(tester);
      await openCollection(tester, 'After prayer');
      expect(find.text('0 of 11 today'), findsOneWidget);
      expect(find.text('Tap a dhikr each time you say it.'), findsOneWidget);
      expect(counter('pr01', '1'), findsOneWidget);
      await tapCard(tester, 'pr01');
      expect(progress(tester), '1 of 11 today');
      // The list moved on; back up, the first one wears its check.
      await tester.scrollUntilVisible(card('pr01'), -300, scrollable: find.byType(Scrollable).first);
      await settle(tester);
      expect(doneMark('pr01'), findsOneWidget);
      expect(saved()['day'], '2026-11-04');
      expect(saved()['counts'], {'prayer/pr01': 1});
      // Done is done: another tap changes nothing.
      await tapCard(tester, 'pr01');
      expect(saved()['counts'], {'prayer/pr01': 1});
    });

    testWidgets('33 times: the counter goes down, and the list moves on to the next', (tester) async {
      await launch(tester);
      await openCollection(tester, 'After prayer');
      await tapCard(tester, 'pr04'); // سبحان الله, 33
      expect(counter('pr04', '32'), findsOneWidget);
      final top = tester.getRect(card('pr04')).top;
      for (var i = 0; i < 32; i++) {
        await tester.tapAt(tester.getRect(card('pr04')).topLeft + const Offset(40, 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await settle(tester);
      expect(saved()['counts'], {'prayer/pr04': 33});
      // The next one (الحمد لله) has come up to where this one was.
      expect(tester.getRect(card('pr05')).top, lessThanOrEqualTo(top), reason: 'scrolled to the next dhikr');
      expect(counter('pr05', '33'), findsOneWidget);
    });

    testWidgets('start again, then undo', (tester) async {
      await launch(tester);
      await openCollection(tester, 'After prayer');
      await tapCard(tester, 'pr01');
      await tapCard(tester, 'pr02');
      expect(progress(tester), '2 of 11 today');
      await tester.tap(find.byTooltip('Start again'));
      await settle(tester);
      expect(progress(tester), '0 of 11 today');
      expect(saved()['counts'], isEmpty);
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(progress(tester), '2 of 11 today');
      expect(saved()['counts'], {'prayer/pr01': 1, 'prayer/pr02': 1});
    });

    const counts = {
      AdhkarStore.key: '{"v":1,"day":"2026-11-04","counts":{"morning/me03":1,"morning/me04":1}}',
    };

    testWidgets('kept through the day', (tester) async {
      await launch(tester, counts);
      await openAdhkar(tester);
      expect(find.text('2 of 22 today'), findsOneWidget, reason: 'the morning');
      expect(find.text('After Asr'), findsOneWidget, reason: 'the evening is counted apart');
    });

    testWidgets('a new day starts from zero', (tester) async {
      await launch(tester, counts, DateTime(2026, 11, 5, 7));
      await openAdhkar(tester);
      expect(find.text('2 of 22 today'), findsNothing);
      expect(find.text('After Fajr'), findsOneWidget);
    });

    testWidgets('a whole collection said: done today, and a closing word', (tester) async {
      final all = {for (final d in loadAdhkar().of(AdhkarCollection.sleep)) 'sleep/${d.id}': d.count};
      await launch(tester, {
        AdhkarStore.key: jsonEncode({'v': 1, 'day': '2026-11-04', 'counts': all}),
      });
      await openAdhkar(tester);
      expect(find.text('Done today'), findsOneWidget);
      await tester.tap(find.text('Before sleep'));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('All done. May Allah accept it from you.'), 300);
      expect(find.text('All done. May Allah accept it from you.'), findsOneWidget);
    });
  });

  group('what a card shows', () {
    testWidgets('the evening’s own words; the meaning and the sources', (tester) async {
      await launch(tester);
      await openCollection(tester, 'Evening adhkar');
      await show(tester, 'me03');
      expect(find.textContaining('أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ،'), findsOneWidget);
      expect(find.textContaining('We have reached the evening'), findsWidgets);
      expect(find.text('Muslim'), findsWidgets);
      await tester.scrollUntilVisible(card('me02'), -300, scrollable: find.byType(Scrollable).first);
      await settle(tester);
      expect(find.text('Abu Dawud and al-Tirmidhi'), findsOneWidget, reason: 'the three Quls');
    });

    testWidgets('Quran is shown from the app’s text, and opens its translation', (tester) async {
      await launch(tester);
      await openCollection(tester, 'Morning adhkar');
      final kursi = card('me01');
      final ayah = loadQuran().verse(loadQuran().verseId(2, 255)!).uthmani;
      expect(find.descendant(of: kursi, matching: find.text('Al-Baqarah 2:255')), findsOneWidget);
      expect(find.descendant(of: kursi, matching: find.textContaining(ayah.substring(0, 20), findRichText: true)),
          findsOneWidget);
      expect(find.text('Al-Nasa’i and al-Hakim'), findsOneWidget, reason: 'capitalised at the start');
      final study = find.descendant(of: kursi, matching: find.text('Translation and tafsir'));
      await tester.ensureVisible(study);
      await settle(tester);
      await tester.tap(study);
      await settle(tester);
      expect(find.byType(StudyScreen), findsOneWidget);
      expect(h.prefs.getString(AdhkarStore.key), isNull, reason: 'the button does not count');
    });

    testWidgets('Arabic interface: no meaning (the words are the text), sources in Arabic', (tester) async {
      await launch(tester, {'language': 'ar'});
      await tapNav(tester, 'المزيد');
      await tester.tap(find.text('الأذكار'));
      await settle(tester);
      await tester.tap(find.text('أذكار بعد الصلاة'));
      await settle(tester);
      expect(find.text('0 من 11 اليوم'), findsOneWidget);
      expect(find.textContaining('forgiveness'), findsNothing);
      await show(tester, 'pr02');
      expect(find.text('البخاري ومسلم'), findsOneWidget);
    });

    testWidgets('French interface: the French meaning', (tester) async {
      await launch(tester, {'language': 'fr'});
      await tapNav(tester, 'Plus');
      await tester.tap(find.text('Adhkar'));
      await settle(tester);
      await tester.tap(find.text('Après la prière'));
      await settle(tester);
      expect(find.textContaining('Je demande pardon à Allah (trois fois)'), findsOneWidget);
      await show(tester, 'pr02');
      expect(find.text('Al-Bukhari et Muslim'), findsOneWidget);
    });
  });
}
