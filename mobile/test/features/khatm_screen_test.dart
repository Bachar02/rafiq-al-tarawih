import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/data/khatm.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/khatm/khatm_screen.dart';
import 'package:rafiq/features/reader/reader_screen.dart';

import '../support/app_nav.dart';
import '../support/fakes.dart';

/// A stored khatm book, as the store writes it.
Map<String, Object> khatmPrefs(KhatmPlan plan, {List<KhatmRecord> finished = const []}) =>
    {PrefsReadingStore.khatmKey: jsonEncode(KhatmBook(active: plan, finished: finished).toJson())};

/// A plan started on Nov 1 (the harness's today is Nov 4) with [read] pages read on Nov 1.
KhatmPlan planWith({Iterable<int> read = const [], int startPage = 1, DateTime? endsOn}) =>
    KhatmPlan(startedOn: DateTime(2026, 11, 1), endsOn: endsOn ?? DateTime(2026, 11, 30), startPage: startPage)
        .reading(DateTime(2026, 11, 1), read);

Iterable<int> pages(int from, int to) => [for (var p = from; p <= to; p++) p];

void main() {
  final quran = loadQuran();
  late Harness h;

  Future<ProviderContainer> launch(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
    h = await Harness.create(prefs: prefs);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await tester.pump();
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
  }

  Future<void> openPlanner(WidgetTester tester) async {
    await tapNav(tester, 'More');
    await tester.tap(find.text('Khatm planner'));
    await tester.pumpAndSettle();
  }

  KhatmBook saved() => PrefsReadingStore(h.prefs).khatm();

  /// Scroll [text] into view and tap it, as a user would.
  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('start a 15-day khatm from the beginning', (tester) async {
    await launch(tester, prefs: {'reading_position.v1': '{"v":1,"verse":262,"at":"2026-11-04T18:00:00.000Z"}'});
    await openPlanner(tester);
    expect(find.text('Where I am reading'), findsOneWidget);
    expect(find.text('Page 42'), findsOneWidget);
    expect(find.text('About 21 pages a day · ends Dec 3, 2026'), findsOneWidget, reason: '30 days by default');

    await tester.tap(find.text('15 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('From the beginning'));
    await tester.pumpAndSettle();
    expect(find.text('About 41 pages a day · ends Nov 18, 2026'), findsOneWidget);
    await tapText(tester, 'Start khatm');

    final plan = saved().active!;
    expect(plan.startedOn, DateTime(2026, 11, 4));
    expect(plan.endsOn, DateTime(2026, 11, 18));
    expect(plan.startPage, 1);
    expect(find.text('0 of 604 pages read'), findsOneWidget);
    expect(find.text('Today: 0 of 41 pages'), findsOneWidget);
    expect(find.text('15 days left · ends Nov 18, 2026'), findsOneWidget);
    expect(find.text('Continue khatm (page 1)'), findsOneWidget);
  });

  testWidgets('a picked date sets the end', (tester) async {
    await launch(tester);
    await openPlanner(tester);
    expect(find.text('Where I am reading'), findsNothing, reason: 'on page 1 there is one way to start');
    await tester.tap(find.text('Pick a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // The picker opened on the default end, in December.
    expect(find.text('Dec 20, 2026'), findsOneWidget);
    expect(find.text('About 13 pages a day · ends Dec 20, 2026'), findsOneWidget); // ceil(604 / 47)
    await tapText(tester, 'Start khatm');
    expect(saved().active!.endsOn, DateTime(2026, 12, 20));
  });

  testWidgets('a start that cannot be saved says so and shows no plan', (tester) async {
    h = await Harness.create();
    h.readingStore = FailingStore(PrefsReadingStore(h.prefs));
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await tester.pumpAndSettle();
    await openPlanner(tester);
    await tapText(tester, 'Start khatm');
    expect(find.text('Could not save the khatm plan. Try again.'), findsOneWidget);
    expect(find.text('Start khatm'), findsOneWidget);
  });

  testWidgets('continue opens the first unread page in the reader', (tester) async {
    final container = await launch(tester, prefs: khatmPrefs(planWith(read: pages(1, 10))));
    await openPlanner(tester);
    expect(find.text('10 of 604 pages read'), findsOneWidget);
    expect(find.text('Today: 0 of 22 pages'), findsOneWidget); // ceil(594 / 27)
    await tapText(tester, 'Continue khatm (page 11)');
    expect(find.byType(KhatmScreen), findsNothing);
    expect(quran.pageOf(container.read(readingPositionProvider)), 11);
  });

  testWidgets('change the end date', (tester) async {
    await launch(tester, prefs: khatmPrefs(planWith()));
    await openPlanner(tester);
    await tapText(tester, 'Change end date');
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(saved().active!.endsOn, DateTime(2026, 11, 20));
    expect(find.text('17 days left · ends Nov 20, 2026'), findsOneWidget);
  });

  testWidgets('overdue: past the planned end, and what is left', (tester) async {
    await launch(tester, prefs: khatmPrefs(planWith(read: pages(1, 600), endsOn: DateTime(2026, 11, 2))));
    await openPlanner(tester);
    expect(find.text('Past the planned end · 4 pages left'), findsOneWidget);
    expect(find.text('Today: 0 of 4 pages'), findsOneWidget);
  });

  testWidgets('stop asks first; cancelling keeps the plan', (tester) async {
    await launch(tester, prefs: khatmPrefs(planWith(read: pages(1, 3))));
    await openPlanner(tester);
    await tapText(tester, 'Stop this khatm');
    expect(find.text('Stop this khatm?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saved().active, isNotNull);

    await tapText(tester, 'Stop this khatm');
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(saved().active, isNull);
    expect(find.text('Start khatm'), findsOneWidget);
  });

  testWidgets('finished khatms are listed', (tester) async {
    await launch(
      tester,
      prefs: {
        PrefsReadingStore.khatmKey: jsonEncode(KhatmBook(finished: [
          KhatmRecord(startedOn: DateTime(2026, 10, 1), completedOn: DateTime(2026, 10, 29)),
        ]).toJson()),
      },
    );
    await openPlanner(tester);
    expect(find.text('Finished khatms'.toUpperCase()), findsOneWidget);
    expect(find.text('Completed Oct 29, 2026'), findsOneWidget);
    expect(find.text('in 29 days'), findsOneWidget);
  });

  testWidgets('the reader bar shows the khatm target instead of the daily goal', (tester) async {
    final container = await launch(tester, prefs: {'daily_goal_pages': 5, ...khatmPrefs(planWith())});
    expect(find.text('Juz 1 · Page 1 · Today 0/23'), findsOneWidget); // ceil(604 / 27)
    expect(find.bySemanticsLabel(RegExp('Khatm: 0 of 23 pages read today')), findsOneWidget);
    container.read(readingProgressProvider.notifier)
      ..jumpedTo(1)
      ..movedTo(2)
      ..movedTo(3);
    await tester.pump();
    expect(find.textContaining('Today 2/23'), findsOneWidget, reason: "today's reading does not shrink today's target");

    await container.read(khatmProvider.notifier).stop();
    await tester.pump();
    expect(find.textContaining('Today 2/5'), findsOneWidget, reason: 'no plan: the daily goal again');
  });

  testWidgets('the Bookmarks card shows the khatm and opens the planner', (tester) async {
    await launch(tester, prefs: khatmPrefs(planWith(read: pages(1, 30))));
    await tapNav(tester, 'Bookmarks');
    expect(find.text('30 of 604 pages'), findsOneWidget);
    expect(find.text('Today 0/22 · 27 days left · ends Nov 30, 2026'), findsOneWidget); // ceil(574 / 27)
    await tester.tap(find.text('30 of 604 pages'));
    await tester.pumpAndSettle();
    expect(find.byType(KhatmScreen), findsOneWidget);
  });

  testWidgets('no plan: no card on Bookmarks', (tester) async {
    await launch(tester);
    await tapNav(tester, 'Bookmarks');
    expect(find.text('KHATM'), findsNothing);
  });

  testWidgets('reading the last pages completes the khatm, said once', (tester) async {
    final container = await launch(
      tester,
      prefs: {
        'reading_layout': 'pages',
        'reading_position.v1': '{"v":1,"verse":${quran.pages.start(603)},"at":"2026-11-04T18:00:00.000Z"}',
        ...khatmPrefs(planWith(read: pages(1, 602))),
      },
    );
    await tester.fling(find.byType(PageView), const Offset(200, 0), 800);
    await tester.pumpAndSettle();
    expect(container.read(khatmProvider).active, isNull);
    expect(find.text('Khatm complete · in 4 days'), findsOneWidget);
    await container.read(khatmProvider.notifier).flush();
    expect(saved().finished.single.completedOn, DateTime(2026, 11, 4));
  });
}
