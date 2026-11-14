import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/features/adhkar/adhkar_screen.dart' show DhikrCard;
import 'package:rafiq/features/duas/duas_screen.dart';

import '../support/app_nav.dart';
import '../support/fakes.dart';

void main() {
  late Harness h;

  Future<void> launch(WidgetTester tester, [Map<String, Object> prefs = const {}]) async {
    h = await Harness.create(prefs: {'taraweeh_intro_seen': true, ...prefs});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, String more, String duas, String purpose) async {
    await tapNav(tester, more);
    await tester.tap(find.text(duas));
    await tester.pumpAndSettle();
    expect(find.byType(DuasScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text(purpose), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text(purpose));
    await tester.pumpAndSettle();
  }

  /// The card of dua [id] (Arabic cards are tall under the test font: found by id, scrolled to).
  Future<Finder> card(WidgetTester tester, String id) async {
    final finder = find.byWidgetPredicate((w) => w is DhikrCard && w.dhikr.id == id);
    await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).last);
    return finder;
  }

  testWidgets('More → Duas: the purposes, each with how many', (tester) async {
    await launch(tester);
    await tapNav(tester, 'More');
    expect(find.text('For forgiveness, worry, travel, illness and more'), findsOneWidget);
    await tester.tap(find.text('Duas'));
    await tester.pumpAndSettle();
    expect(find.text('Forgiveness and repentance'), findsOneWidget);
    expect(find.text('4 duas'), findsWidgets);
    await tester.scrollUntilVisible(find.text('From the Quran'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('From the Quran'), findsOneWidget);
  });

  testWidgets('a purpose: each dua in Arabic, how it is said, what it means, who reports it', (tester) async {
    await launch(tester);
    await open(tester, 'More', 'Duas', 'Travel');
    expect(find.byType(DuaListScreen), findsOneWidget);
    final travel = await card(tester, 'tr03');
    expect(find.descendant(of: travel, matching: find.textContaining('أَعُوذُ بِكَلِمَاتِ اللَّهِ')), findsOneWidget);
    expect(find.descendant(of: travel, matching: find.text('A’udhu bi-kalimatillahit-tammati min sharri ma khalaq')),
        findsOneWidget);
    expect(find.descendant(of: travel, matching: find.textContaining('perfect words of Allah')), findsOneWidget);
    expect(find.descendant(of: travel, matching: find.text('Muslim')), findsOneWidget);
  });

  testWidgets('read, not counted: no counter, and “7 times” where it is said seven times', (tester) async {
    await launch(tester);
    await open(tester, 'More', 'Duas', 'Illness and healing');
    final seven = await card(tester, 'hl02');
    expect(find.descendant(of: seven, matching: find.text('7 times')), findsOneWidget);
    await tester.tap(seven);
    await tester.pumpAndSettle();
    expect(find.descendant(of: seven, matching: find.text('7 times')), findsOneWidget, reason: 'a tap counts nothing');
  });

  testWidgets('from the Quran: the ayahs from the app’s text, with their translation', (tester) async {
    await launch(tester);
    await open(tester, 'More', 'Duas', 'Parents and family');
    final parents = await card(tester, 'fm01');
    expect(find.descendant(of: parents, matching: find.textContaining('17:24')), findsOneWidget);
    expect(find.descendant(of: parents, matching: find.text('The Quran')), findsOneWidget);
    expect(find.descendant(of: parents, matching: find.text('Translation and tafsir')), findsOneWidget);
  });

  testWidgets('in Arabic: the words alone, no Latin letters', (tester) async {
    await launch(tester, {'language': 'ar'});
    await open(tester, 'المزيد', 'الأدعية', 'السفر');
    final travel = await card(tester, 'tr03');
    expect(find.descendant(of: travel, matching: find.textContaining('A’udhu')), findsNothing);
    expect(find.descendant(of: travel, matching: find.text('مسلم')), findsOneWidget);
  });
}
