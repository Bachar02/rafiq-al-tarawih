/// Golden screenshots of the Rubric screens, rendered with the app's real
/// fonts (test/golden/README.md). The widget tests use the Ahem test font, so
/// they cannot see a missing glyph or text that overflows only in the real
/// typefaces; these can.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/features/reader/widgets/taraweeh_entry.dart';

import '../support/fakes.dart';
import '../support/golden.dart';

/// A common Android phone (logical pixels), and the smallest screen supported.
const phone = Size(360, 780);
const smallPhone = Size(320, 568);

/// Device pixel ratio of every render: enough to show glyph detail, small files.
const ratio = 2.0;

void main() {
  late Harness h;

  /// Let transitions and scrolling finish (fixed steps: spinners never settle).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The app opens on the reader; [taraweeh] then enters Taraweeh mode.
  Future<void> launch(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    Size size = phone,
    bool taraweeh = true,
  }) async {
    // The one-time introduction has been seen: entering starts following.
    h = await Harness.create(prefs: {'taraweeh_intro_seen': true, ...prefs});
    tester.view.physicalSize = size * ratio;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await tester.pump();
    if (taraweeh) {
      await tester.tap(find.byType(TaraweehEntry)); // in any language
      await settle(tester);
    }
  }

  /// Entering Taraweeh mode started a session: the engine becomes ready.
  Future<void> startListening(WidgetTester tester) async {
    h.engine.emit(const EngineReady());
    await settle(tester);
  }

  Future<void> hear(WidgetTester tester, TrackState state) async {
    h.engine.emit(heard(state));
    await settle(tester);
  }

  /// Image assets (the wordmark) decode on real I/O, outside the test's fake
  /// clock: wait for every one on screen, or a capture may miss it.
  Future<void> loadImages(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
    await tester.pump();
  }

  Future<void> expectGolden(WidgetTester tester, String name) async {
    await loadImages(tester);
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(RafiqApp), matchesGoldenFile('screens/$name.png'));
  }

  /// A saved reading position, as the reading store writes it.
  Map<String, Object> readingAt(int surah, int ayah) => {
        'reading_position.v1': '{"v":1,"verse":${loadQuran().verseId(surah, ayah)},"at":"2026-11-04T18:00:00.000Z"}',
      };

  group('Rubric screens', skip: goldenSkipReason, () {
    testWidgets('Taraweeh introduction, shown once', (tester) async {
      await launch(tester, prefs: {'taraweeh_intro_seen': false});
      await expectGolden(tester, 'taraweeh_intro');
    });

    testWidgets('reader: Al-Baqarah opens with its header, dark', (tester) async {
      await launch(tester, prefs: {...readingAt(2, 1), 'theme_mode': 'dark'}, taraweeh: false);
      await settle(tester);
      await expectGolden(tester, 'reader_dark');
    });

    testWidgets('reader: a juz and page mark, light', (tester) async {
      await launch(tester, prefs: {...readingAt(2, 140), 'theme_mode': 'light'}, taraweeh: false);
      await settle(tester);
      await expectGolden(tester, 'reader_light');
    });

    testWidgets('daily goal on a 320 px phone: the page stays in view', (tester) async {
      await launch(
        tester,
        prefs: {...readingAt(78, 1), 'daily_goal_pages': 20, 'theme_mode': 'light'},
        size: smallPhone,
        taraweeh: false,
      );
      await settle(tester);
      await expectGolden(tester, 'reader_goal_small_phone');
    });

    testWidgets('page view: page 42, light', (tester) async {
      await launch(
        tester,
        prefs: {...readingAt(2, 253), 'reading_layout': 'pages', 'theme_mode': 'light'},
        taraweeh: false,
      );
      await settle(tester);
      await expectGolden(tester, 'reader_pages');
    });

    testWidgets('page view: page 582 opens juz 30, dark', (tester) async {
      await launch(tester,
          prefs: {...readingAt(78, 1), 'reading_layout': 'pages', 'theme_mode': 'dark'}, taraweeh: false);
      await settle(tester);
      await expectGolden(tester, 'reader_pages_dark');
    });

    testWidgets('share an ayah: the image card, dark', (tester) async {
      await launch(tester, prefs: {...readingAt(2, 255), 'theme_mode': 'dark'}, taraweeh: false);
      await settle(tester);
      final quran = loadQuran();
      final ayah = find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == quran.verseId(2, 255));
      tester.widget<AyahBlock>(ayah.first).onTap!();
      await settle(tester);
      await tester.tap(find.text('Share'));
      await settle(tester);
      await expectGolden(tester, 'share_card');
    });

    testWidgets('Arabic interface: the reader, right to left', (tester) async {
      await launch(tester, prefs: {...readingAt(2, 140), 'language': 'ar', 'theme_mode': 'dark'}, taraweeh: false);
      await settle(tester);
      await expectGolden(tester, 'ar_reader');
    });

    testWidgets('Arabic interface: following 93:3', (tester) async {
      await launch(tester, prefs: {'language': 'ar'});
      await startListening(tester);
      await hear(tester, at(93, 3));
      await expectGolden(tester, 'ar_following');
    });

    testWidgets('French interface: settings', (tester) async {
      await launch(tester, prefs: {'language': 'fr', 'theme_mode': 'light'}, taraweeh: false);
      await tester.tap(find.byTooltip('Réglages'));
      await settle(tester);
      await expectGolden(tester, 'fr_settings');
    });

    testWidgets('search: Arabic words, without tashkeel', (tester) async {
      await launch(tester, prefs: {'theme_mode': 'dark'}, taraweeh: false);
      await tester.tap(find.byTooltip('Search the Quran'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'الحي القيوم');
      await settle(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      await expectGolden(tester, 'search');
    });

    testWidgets('go to: bookmarks and where Taraweeh ended, light', (tester) async {
      final at = DateTime.now().toUtc().toIso8601String();
      final quran = loadQuran();
      await launch(
        tester,
        prefs: {
          ...readingAt(18, 10),
          'theme_mode': 'light',
          'bookmarks.v1': '{"v":1,"items":[{"verse":${quran.verseId(18, 10)},"at":"$at"},'
              '{"verse":${quran.verseId(2, 255)},"at":"$at"}]}',
          'taraweeh_position.v1': '{"v":1,"verse":${quran.verseId(5, 81)},"at":"$at"}',
        },
        taraweeh: false,
      );
      await tester.tap(find.byTooltip('Surahs, juz and bookmarks'));
      await settle(tester);
      await tester.tap(find.text('Bookmarks'));
      await settle(tester);
      await expectGolden(tester, 'navigate_bookmarks');
    });

    testWidgets('reader: 320×568 at the largest Quran text, in juz 30', (tester) async {
      await launch(tester, prefs: {...readingAt(78, 1), 'text_scale': 1.6}, size: smallPhone, taraweeh: false);
      await settle(tester);
      await expectGolden(tester, 'reader_small_phone');
    });

    testWidgets('following 93:3, dark', (tester) async {
      await launch(tester);
      await startListening(tester);
      await hear(tester, at(93, 3));
      await expectGolden(tester, 'following_dark');
    });

    testWidgets('following 93:3, light', (tester) async {
      await launch(tester, prefs: {'theme_mode': 'light', 'dark_during_taraweeh': false});
      await startListening(tester);
      await hear(tester, at(93, 3));
      await expectGolden(tester, 'following_light');
    });

    testWidgets('not sure on 2:255: the last sure ayah is held', (tester) async {
      await launch(tester);
      await startListening(tester);
      await hear(tester, at(2, 255));
      await hear(tester, at(2, 255, status: TrackStatus.uncertain));
      await expectGolden(tester, 'not_sure');
    });

    testWidgets('Al-Fatiha excursion: 55:13 stays while 1:3 is recited', (tester) async {
      await launch(tester);
      await startListening(tester);
      await hear(tester, at(55, 13));
      await hear(tester, at(1, 3));
      await expectGolden(tester, 'fatiha_excursion');
    });

    testWidgets('320×568, Quran text 1.3 and system text 1.3, on 2:282', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await launch(tester, prefs: {'text_scale': 1.3}, size: smallPhone);
      await startListening(tester);
      await hear(tester, at(2, 282));
      await expectGolden(tester, 'small_phone_2_282');
    });

    testWidgets('error Notice: the server cannot be reached', (tester) async {
      await launch(tester);
      h.engine.emit(
          const EngineFailure('Cannot reach the recognition server at 10.0.2.2:8765', kind: FailureKind.unreachable));
      await settle(tester);
      await expectGolden(tester, 'error_notice');
    });

    testWidgets('settings', (tester) async {
      await launch(tester);
      await tester.tap(find.byTooltip('Settings'));
      await settle(tester);
      await expectGolden(tester, 'settings');
    });

    testWidgets('hint sheet', (tester) async {
      await launch(tester);
      await tester.tap(find.byTooltip("Tonight's starting point"));
      await settle(tester);
      await expectGolden(tester, 'hint_sheet');
    });
  });
}
