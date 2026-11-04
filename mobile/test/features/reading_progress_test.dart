import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/quran_view/quran_view.dart';
import 'package:rafiq/features/reader/reader_screen.dart';
import 'package:rafiq/features/reader/reading_progress.dart';

import '../support/fakes.dart';

void main() {
  final quran = loadQuran();

  group('ReadingLog', () {
    final day = DateTime(2026, 11, 4, 20);

    test('adds pages to the day, keeps 90 days, round-trips', () {
      var log = const ReadingLog().adding(day, [1, 2]).adding(day, [2, 3]);
      expect(log.on(day), {1, 2, 3});
      log = log.adding(day.add(const Duration(days: 91)), [9]);
      expect(log.on(day), isEmpty, reason: 'older than 90 days is dropped');
      final back = ReadingLog.fromJson(log.toJson())!;
      expect(back.on(day.add(const Duration(days: 91))), {9});
    });

    test('an unreadable log is kept aside and reads as empty', () async {
      final h = await Harness.create(prefs: {PrefsReadingStore.logKey: '{"v":1,"days":[]}'});
      final store = PrefsReadingStore(h.prefs);
      expect(store.readingLog().days, isEmpty);
      await store.saveReadingLog(const ReadingLog().adding(day, [5]));
      expect(h.prefs.getKeys().where((k) => k.contains('.unreadable.')).map(h.prefs.getString), ['{"v":1,"days":[]}']);
    });
  });

  group('ReadingProgressController', () {
    late Harness h;
    late ProviderContainer c;
    ReadingProgressController progress() => c.read(readingProgressProvider.notifier);

    setUp(() async {
      h = await Harness.create();
      c = h.container();
      addTearDown(c.dispose);
    });

    test('moving forward page by page counts the pages left behind', () {
      progress().jumpedTo(10);
      progress().movedTo(11);
      progress().movedTo(12);
      expect(c.read(readingProgressProvider).on(h.now), {10, 11});
      expect(progress().today, 2);
    });

    test('a fast scroll that skips a page still counts both', () {
      progress().jumpedTo(10);
      progress().movedTo(12);
      expect(progress().today, 2);
    });

    test('jumps, big leaps and going back count nothing', () {
      progress().jumpedTo(10);
      progress().movedTo(50); // more than two pages: a jump
      progress().movedTo(49); // backwards
      progress().jumpedTo(100);
      progress().movedTo(100);
      expect(progress().today, 0);
    });

    test('reaching the last page counts it', () {
      progress().jumpedTo(603);
      progress().movedTo(604);
      expect(c.read(readingProgressProvider).on(h.now), {603, 604});
    });

    test('a new day starts from zero; the past day is kept', () async {
      progress().jumpedTo(1);
      progress().movedTo(2);
      final yesterday = h.now;
      h.now = h.now.add(const Duration(hours: 5)); // past midnight
      expect(progress().today, 0);
      progress().movedTo(3);
      expect(progress().today, 1);
      expect(c.read(readingProgressProvider).on(yesterday), {1});
      expect(await progress().flush(), isTrue);
      expect(PrefsReadingStore(h.prefs).readingLog().on(h.now), {2});
    });
  });

  group('the daily goal in the reader', () {
    late Harness h;

    Future<ProviderContainer> launch(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
      await tester.pump();
      await tester.pump();
      return ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
    }

    testWidgets('no goal: nothing extra in the bar', (tester) async {
      h = await Harness.create();
      await launch(tester);
      expect(find.textContaining('Today'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('reading forward fills today; a search jump does not', (tester) async {
      h = await Harness.create(prefs: {'daily_goal_pages': 20});
      final container = await launch(tester);
      expect(find.text('Juz 1 · Page 1 · Today 0/20'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('0 of 20 pages read today')), findsOneWidget);

      // Read on through page 2 into page 3.
      for (var i = 0; i < 12 && quran.pageOf(container.read(readingPositionProvider)) < 3; i++) {
        await tester.drag(find.byType(QuranView), const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(quran.pageOf(container.read(readingPositionProvider)), greaterThanOrEqualTo(3));
      expect(container.read(readingProgressProvider.notifier).today, greaterThanOrEqualTo(2));
      final before = container.read(readingProgressProvider.notifier).today;

      tester.state<ReaderScreenState>(find.byType(ReaderScreen)).openAt(quran.verseId(2, 255)!, mark: false);
      await tester.pumpAndSettle();
      expect(container.read(readingProgressProvider.notifier).today, before, reason: 'a jump is not reading');
    });

    testWidgets('turning pages in the page view fills today', (tester) async {
      h = await Harness.create(prefs: {'daily_goal_pages': 5, 'reading_layout': 'pages'});
      final container = await launch(tester);
      for (var i = 0; i < 3; i++) {
        await tester.fling(find.byType(PageView), const Offset(200, 0), 800);
        await tester.pumpAndSettle();
      }
      expect(container.read(readingProgressProvider).on(h.now), {1, 2, 3});
      expect(find.textContaining('Today 3/5'), findsOneWidget);
    });

    testWidgets('the goal is chosen in settings', (tester) async {
      h = await Harness.create();
      await launch(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Daily reading goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20 pages'));
      await tester.pumpAndSettle();
      expect(h.prefs.getInt('daily_goal_pages'), 20);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('Today 0/20'), findsOneWidget);
    });
  });
}
