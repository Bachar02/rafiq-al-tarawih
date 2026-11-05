/// Flutter's accessibility guidelines on every main screen, in both themes:
/// tap targets (48 dp Android, 44 dp iOS), a label on every tap target, and
/// text contrast. Large system text is covered by the small-phone tests.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/core/recognition/models.dart';

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
        await tester.pageBack();
        await settle(tester);
        await tapNav(tester, 'Bookmarks');
        await meetsGuidelines(tester);
      });

      testWidgets('settings', (tester) async {
        await launch(tester, {'theme_mode': theme});
        await openSettings(tester);
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
    });
  }

  testWidgets('200% system text: every main screen lays out without overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, {'daily_goal_pages': 20});
    expect(tester.takeException(), isNull, reason: 'reader');
    for (final tab in ['Surahs', 'Bookmarks', 'More', 'Read']) {
      await tapNav(tester, tab);
      expect(tester.takeException(), isNull, reason: tab);
    }
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
