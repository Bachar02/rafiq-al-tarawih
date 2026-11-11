import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/features/listen/listen_screen.dart';
import 'package:rafiq/features/reader/reader_screen.dart';
import 'package:rafiq/l10n/l10n.dart';

import '../support/fakes.dart';
import '../support/app_nav.dart';

Map<String, dynamic> arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map<String, dynamic>;

/// `{name}` placeholders of a message. Placeholders are lower-camel
/// identifiers; plural branch texts (`=0{Bookmarks}`) are not.
Set<String> placeholders(String message) => {for (final m in RegExp(r'\{([a-z]\w*)[,}]').allMatches(message)) m[1]!};

void main() {
  group('translations', () {
    final en = arb('en');
    final keys = {
      for (final k in en.keys)
        if (!k.startsWith('@')) k
    };

    for (final locale in ['fr', 'ar']) {
      test('$locale has every message, with the same placeholders', () {
        final other = arb(locale);
        final theirs = {
          for (final k in other.keys)
            if (!k.startsWith('@')) k
        };
        expect(theirs.difference(keys), isEmpty, reason: 'keys not in English');
        expect(keys.difference(theirs), isEmpty, reason: 'untranslated');
        for (final k in keys) {
          expect(placeholders(other[k] as String), placeholders(en[k] as String), reason: '$locale: $k');
        }
      });
    }

    test('Arabic plurals use the Arabic forms', () {
      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(ar.ayahCount(1), 'آية واحدة');
      expect(ar.ayahCount(2), 'آيتان');
      expect(ar.ayahCount(7), '7 آيات');
      expect(ar.ayahCount(11), '11 آية');
      expect(ar.ayahCount(286), '286 آية');
      final fr = lookupAppLocalizations(const Locale('fr'));
      expect(fr.ayahCount(1), '1 verset');
      expect(fr.ayahCount(286), '286 versets');
    });

    test('the phone language decides when the user has not chosen', () {
      expect(resolveAppLocale(const [Locale('ar', 'TN'), Locale('fr')]), const Locale('ar'));
      expect(resolveAppLocale(const [Locale('de'), Locale('fr', 'FR')]), const Locale('fr'));
      expect(resolveAppLocale(const [Locale('de')]), const Locale('en'));
    });
  });

  group('the app in each language', () {
    late Harness h;

    Future<void> launch(WidgetTester tester, String language, {Size size = const Size(1080, 2340)}) async {
      h = await Harness.create(prefs: {'language': language, 'taraweeh_intro_seen': true});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('Arabic: right to left, Arabic names and words', (tester) async {
      await launch(tester, 'ar');
      final reader = tester.element(find.byType(ReaderScreen));
      expect(Directionality.of(reader), TextDirection.rtl);
      expect(find.bySemanticsLabel(RegExp('^الفاتحة، الآية 1. الجزء 1، الصفحة 1')), findsOneWidget);
      expect(find.byTooltip('البحث في القرآن'), findsOneWidget);

      await tester.tap(taraweehButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(Directionality.of(tester.element(find.byType(ListenScreen))), TextDirection.rtl);
      expect(find.text('جارٍ التهيئة…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('French: the reader and Taraweeh mode', (tester) async {
      await launch(tester, 'fr');
      expect(find.bySemanticsLabel(RegExp('^Al-Fatiha, verset 1. Juz 1, page 1')), findsOneWidget);
      await tester.tap(taraweehButton);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Mise en route…'), findsOneWidget);
    });

    testWidgets('choosing a language in settings applies at once and is kept', (tester) async {
      await launch(tester, 'system');
      await openSettings(tester);
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();
      expect(find.text('الإعدادات'), findsWidgets);
      expect(h.prefs.getString('language'), 'ar');
      final container = ProviderScope.containerOf(tester.element(find.byType(ReaderScreen, skipOffstage: false)));
      expect(container.read(surahNamesProvider).of(2), 'البقرة');
    });

    for (final language in ['ar', 'fr', 'en']) {
      testWidgets('$language: a small phone with large system text does not overflow', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await launch(tester, language, size: const Size(960, 1704)); // 320 × 568
        expect(tester.takeException(), isNull);
        await tapNav(tester, switch (language) { 'ar' => 'السور', 'fr' => 'Sourates', _ => 'Surahs' });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
