import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/data/khatm.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/quran_view/quran_view.dart';
import 'package:rafiq/features/reader/page_dwell.dart';
import 'package:rafiq/features/reader/reader_screen.dart';
import 'package:rafiq/features/reader/reading_session.dart';

import '../support/fakes.dart';
import '../support/app_nav.dart';

void main() {
  final quran = loadQuran();
  const s = Duration(seconds: 1);

  group('ReadingLog', () {
    final day = DateTime(2026, 11, 4, 20);

    test('adds pages to the day, keeps 400 days, round-trips', () {
      var log = const ReadingLog().adding(day, [1, 2]).adding(day, [2, 3]);
      expect(log.on(day), {1, 2, 3});
      log = log.adding(day.add(const Duration(days: 366)), [7]);
      expect(log.on(day), {1, 2, 3}, reason: 'a year later the day is still there, for the year chart');
      log = log.adding(day.add(const Duration(days: 401)), [9]);
      expect(log.on(day), isEmpty, reason: 'older than 400 days is dropped');
      final back = ReadingLog.fromJson(log.toJson())!;
      expect(back.on(day.add(const Duration(days: 401))), {9});
      expect(back.on(day.add(const Duration(days: 366))), {7});
    });

    test('merging and removing work day by day', () {
      final a = const ReadingLog().adding(day, [1, 2]);
      final b = const ReadingLog().adding(day, [2, 3]).adding(day.add(const Duration(days: 1)), [4]);
      final both = a.merging(b);
      expect(both.on(day), {1, 2, 3});
      expect(both.length, 4);
      final left = both.removing(b);
      expect(left.on(day), {1});
      expect(left.days.keys, [ReadingLog.dayKey(day)], reason: 'empty days are dropped');
      expect(left.removing(a).isEmpty, isTrue);
    });

    test('an unreadable log is kept aside and reads as empty', () async {
      final h = await Harness.create(prefs: {PrefsReadingStore.logKey: '{"v":1,"days":[]}'});
      final store = PrefsReadingStore(h.prefs);
      expect(store.readingLog().days, isEmpty);
      await store.saveReadingLog(const ReadingLog().adding(day, [5]));
      expect(h.prefs.getKeys().where((k) => k.contains('.unreadable.')).map(h.prefs.getString), ['{"v":1,"days":[]}']);
    });
  });

  group('PageDwell: a page counts once it stayed in view long enough to read', () {
    final t0 = DateTime(2026, 11, 4, 20);
    DateTime at(int seconds) => t0.add(Duration(seconds: seconds));
    PageDwell dwell() => PageDwell((_) => const Duration(seconds: 20));

    test('the time a page needs follows its length', () {
      final real = PageDwell.forQuran(quran);
      expect(real.requiredFor(1).inMilliseconds, inInclusiveRange(4000, 6000), reason: 'Al-Fatiha: a short page');
      final full = real.requiredFor(50).inSeconds;
      expect(full, inInclusiveRange(12, 30), reason: 'a full page: some 20 s');
      expect(real.requiredFor(604) < real.requiredFor(50), isTrue, reason: 'the last page is shorter');
    });

    test('flinging through pages counts nothing', () {
      final d = dwell();
      final read = <int>[];
      for (var p = 1; p <= 60; p++) {
        read.addAll(d.show(p, t0.add(Duration(milliseconds: p * 300))));
      }
      read.addAll(d.tick(at(40)));
      expect(read, [60], reason: 'only the page where the fling stopped (at 18 s), once it stayed 20 s');
    });

    test('a page read in two visits counts once the visits add up', () {
      final d = dwell();
      expect(d.show(5, at(0)), isEmpty);
      expect(d.show(6, at(12)), isEmpty);
      expect(d.show(5, at(15)), isEmpty);
      expect(d.remaining(at(15)), const Duration(seconds: 8));
      expect(d.tick(at(23)), [5]);
      expect(d.tick(at(60)), isEmpty, reason: 'once only');
    });

    test('time out of view does not count', () {
      final d = dwell();
      d.show(5, at(0));
      d.show(null, at(10)); // the app went to the background
      expect(d.remaining(at(500)), isNull);
      expect(d.show(5, at(500)), isEmpty);
      expect(d.tick(at(509)), isEmpty);
      expect(d.tick(at(510)), [5]);
    });

    test('a new day starts afresh', () {
      final d = PageDwell((_) => const Duration(seconds: 20));
      final late = DateTime(2026, 11, 4, 23, 59, 50);
      d.show(5, late);
      expect(d.tick(late.add(const Duration(seconds: 20))), [5], reason: 'counts on the new day');
      expect(d.show(6, late.add(s * 25)), isEmpty);
      expect(d.show(5, late.add(s * 30)), isEmpty);
      expect(d.tick(late.add(s * 50)), isEmpty, reason: 'already read today');
    });
  });

  group('ReadingSessionController', () {
    late Harness h;
    late ProviderContainer c;
    ReadingSessionController session() => c.read(readingSessionProvider.notifier);
    ReadingLog pending() => c.read(readingSessionProvider).pending;

    Future<void> start([Map<String, Object> prefs = const {}, ReadingStore Function(Harness)? store]) async {
      h = await Harness.create(prefs: prefs);
      if (store != null) h.readingStore = store(h);
      c = h.container();
      addTearDown(c.dispose);
    }

    /// Stay on [page] in view for [seconds].
    void read(int page, int seconds) {
      session()
        ..setVisible(true)
        ..showPage(page);
      h.now = h.now.add(Duration(seconds: seconds));
      session().setVisible(false); // looks away: the time is accounted
    }

    test('only pages that stayed long enough are proposed, and they are saved', () async {
      await start();
      read(50, 2);
      read(51, 30);
      read(52, 1);
      expect(pending().on(h.now), {51});
      await pumpEventQueue();
      expect(PrefsReadingStore(h.prefs).pendingReading().on(h.now), {51});
      expect(c.read(readingProgressProvider).on(h.now), isEmpty, reason: 'not counted until reviewed');
    });

    test('nothing counts while the reader is out of view', () async {
      await start();
      session()
        ..showPage(50)
        ..setVisible(false);
      h.now = h.now.add(const Duration(minutes: 5));
      session().showPage(51);
      expect(pending().isEmpty, isTrue);
    });

    test('counting adds the ticked pages to the log and the khatm; the rest are set aside', () async {
      await start();
      await c.read(khatmProvider.notifier).start(endsOn: DateTime(2026, 12, 3), startPage: 50);
      read(50, 30);
      read(51, 30);
      read(52, 30);
      final shown = pending();
      final counted = const ReadingLog().adding(h.now, [50, 51]);
      expect(await session().review(shown: shown, counted: counted), isTrue);
      expect(pending().isEmpty, isTrue);
      expect(c.read(readingProgressProvider).on(h.now), {50, 51});
      expect(c.read(khatmProvider).active!.pages.keys.toSet(), {50, 51});
      expect(PrefsReadingStore(h.prefs).readingLog().on(h.now), {50, 51});
      expect(PrefsReadingStore(h.prefs).pendingReading().isEmpty, isTrue);
    });

    test('pages read while the sheet was open keep waiting', () async {
      await start();
      read(50, 30);
      final shown = pending();
      read(51, 30);
      await session().review(shown: shown, counted: shown);
      expect(pending().on(h.now), {51});
    });

    test('a review that cannot be saved changes nothing', () async {
      late FailingStore failing;
      await start(const {}, (h) => failing = FailingStore(PrefsReadingStore(h.prefs))..failing = false);
      read(50, 30);
      failing.failing = true;
      final shown = pending();
      expect(await session().review(shown: shown, counted: shown), isFalse);
      expect(pending().on(h.now), {50}, reason: 'still waiting');
      expect(c.read(readingProgressProvider).on(h.now), isEmpty);
    });

    test('the app asks after a while away, not after a glance elsewhere', () async {
      await start();
      expect(c.read(readingSessionProvider).ask, 0);
      read(50, 30);
      session().appPaused();
      h.now = h.now.add(const Duration(seconds: 40));
      session().appResumed();
      expect(c.read(readingSessionProvider).ask, 0);
      session().appPaused();
      h.now = h.now.add(const Duration(minutes: 5));
      session().appResumed();
      expect(c.read(readingSessionProvider).ask, 1);
    });

    test('pages left from last time: the app asks as it opens', () async {
      await start({PrefsReadingStore.pendingKey: '{"v":1,"days":{"2026-11-03":[7,8]}}'});
      expect(c.read(readingSessionProvider).ask, 1);
      expect(pending().length, 2);
    });

    test('today counts waiting pages, and only new ones for the khatm', () {
      final day = DateTime(2026, 11, 4);
      final log = const ReadingLog().adding(day, [1, 2]);
      final waiting = const ReadingLog().adding(day, [2, 3]);
      expect(pagesReadOn(log, waiting, day), 3);
      final plan = KhatmPlan(startedOn: day, endsOn: DateTime(2026, 12, 3), startPage: 1).reading(day, [3]);
      expect(planPagesReadOn(plan, waiting, day), 2, reason: 'page 3 already in the plan, page 2 waiting');
    });
  });

  group('the reader', () {
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

    /// Time passes on the clock the app reads, and on the test's timers.
    Future<void> wait(WidgetTester tester, Duration d) async {
      h.now = h.now.add(d);
      await tester.pump(d);
    }

    testWidgets('no goal: nothing extra in the bar', (tester) async {
      await launch(tester);
      expect(find.textContaining('Today'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('scrolling fast through pages counts nothing; staying on a page does', (tester) async {
      final container = await launch(tester, prefs: {'daily_goal_pages': 20});
      expect(find.text('Juz 1 · Page 1 · Today 0/20'), findsOneWidget);
      for (var i = 0; i < 8; i++) {
        await tester.fling(find.byType(QuranView), const Offset(0, -1500), 4000);
        await tester.pumpAndSettle();
      }
      final page = quran.pageOf(container.read(readingPositionProvider));
      expect(page, greaterThan(3), reason: 'flung well past the first pages');
      expect(find.textContaining('Today 0/20'), findsOneWidget, reason: 'nothing stayed long enough');

      await wait(tester, const Duration(seconds: 40));
      expect(container.read(readingSessionProvider).pending.on(h.now), {page});
      expect(find.textContaining('Today 1/20'), findsOneWidget, reason: 'waiting pages show in today');
    });

    testWidgets('time stops while another tab or a sheet is shown', (tester) async {
      final container = await launch(tester, prefs: {'daily_goal_pages': 20});
      await tapNav(tester, 'More');
      await wait(tester, const Duration(minutes: 2));
      expect(container.read(readingSessionProvider).pending.isEmpty, isTrue);
      await tapNav(tester, 'Read');
      await wait(tester, const Duration(seconds: 10));
      expect(container.read(readingSessionProvider).pending.on(h.now), {1}, reason: 'Al-Fatiha needs a few seconds');
    });

    testWidgets('turning pages in the page view counts the pages read, not the ones turned past', (tester) async {
      final container = await launch(tester, prefs: {'daily_goal_pages': 5, 'reading_layout': 'pages'});
      await wait(tester, const Duration(seconds: 30)); // page 1, read
      for (var i = 0; i < 3; i++) {
        await tester.fling(find.byType(PageView), const Offset(200, 0), 800);
        await tester.pumpAndSettle(); // pages 2 and 3: turned past
      }
      await wait(tester, const Duration(seconds: 40)); // page 4, read
      expect(container.read(readingSessionProvider).pending.on(h.now), {1, 4});
      expect(find.textContaining('Today 2/5'), findsOneWidget);
    });

    testWidgets('pages from last time: the app asks; untick one and count the rest', (tester) async {
      final container = await launch(tester, prefs: {
        'daily_goal_pages': 20,
        PrefsReadingStore.pendingKey: '{"v":1,"days":{"2026-11-04":[10,11,12]}}',
      });
      await tester.pumpAndSettle();
      expect(find.text('Count this reading?'), findsOneWidget);
      expect(find.text('Count 3 pages'), findsOneWidget);
      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Count 2 pages'));
      await tester.pumpAndSettle();
      expect(find.text('2 pages counted'), findsOneWidget);
      expect(container.read(readingProgressProvider).on(h.now), {10, 11});
      expect(container.read(readingSessionProvider).pending.isEmpty, isTrue, reason: 'the unticked page is set aside');
      expect(PrefsReadingStore(h.prefs).readingLog().on(h.now), {10, 11});
    });

    testWidgets('not now keeps the pages waiting; don\'t count sets them aside', (tester) async {
      final container = await launch(tester, prefs: {
        PrefsReadingStore.pendingKey: '{"v":1,"days":{"2026-11-03":[10]}}',
      });
      await tester.pumpAndSettle();
      expect(find.text('YESTERDAY'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(container.read(readingSessionProvider).pending.length, 1);

      // Back after a while: asked again.
      final session = container.read(readingSessionProvider.notifier)..appPaused();
      h.now = h.now.add(const Duration(minutes: 10));
      session.appResumed();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Don’t count these'));
      await tester.pumpAndSettle();
      expect(container.read(readingSessionProvider).pending.isEmpty, isTrue);
      expect(container.read(readingProgressProvider).isEmpty, isTrue);
    });

    testWidgets('the goal is chosen in settings', (tester) async {
      await launch(tester);
      await openSettings(tester);
      await tester.tap(find.text('Daily reading goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20 pages'));
      await tester.pumpAndSettle();
      expect(h.prefs.getInt('daily_goal_pages'), 20);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapNav(tester, 'Read');
      expect(find.textContaining('Today 0/20'), findsOneWidget);
    });
  });
}
