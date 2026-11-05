import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/text/quran_display.dart';
import 'package:rafiq/features/quran_view/mushaf_page_view.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/listen/listen_screen.dart';
import 'package:rafiq/features/quran_view/quran_view.dart';
import 'package:rafiq/features/reader/reader_screen.dart';
import 'package:rafiq/features/reader/share_ayah_sheet.dart';
import 'package:rafiq/features/reader/reading_position.dart';

import '../support/fakes.dart';
import 'package:rafiq/features/navigate/navigate_screen.dart';
import 'package:rafiq/features/reader/widgets/page_scrubber.dart';
import '../support/app_nav.dart';

void main() {
  final quran = loadQuran();
  int id(int s, int a) => quran.verseId(s, a)!;

  late Harness h;
  setUp(() async => h = await Harness.create());

  Future<ProviderContainer> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await tester.pump();
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
  }

  /// A cold start on the same storage.
  Future<ProviderContainer> restart(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    return launch(tester);
  }

  /// What the index, search and bookmarks do: open the text at a verse.
  void openAt(WidgetTester tester, int verseId) =>
      tester.state<ReaderScreenState>(find.byType(ReaderScreen)).openAt(verseId, mark: false);

  /// Ayah [verseId] in the reader's text (not a sheet's preview of it).
  /// The reader bar, as a screen reader announces it.
  Finder bar(String start) => find.bySemanticsLabel(RegExp('^${RegExp.escape(start)}'));

  Finder ayah(int verseId) => find.descendant(
        of: find.byType(QuranView),
        matching: find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == verseId),
      );

  testWidgets('first run opens at Al-Fatiha, in the reader', (tester) async {
    final container = await launch(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.byType(ListenScreen), findsNothing);
    expect(container.read(readingPositionProvider), 1);
    expect(bar('Al-Fatiha, ayah 1. Juz 1, page 1'), findsOneWidget);
  });

  testWidgets('scrolling moves the reading position; it is saved and restored after a restart', (tester) async {
    var container = await launch(tester);
    openAt(tester, id(2, 100));
    await tester.pump();
    await tester.pump();
    await tester.drag(find.byType(QuranView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final top = container.read(readingPositionProvider);
    expect(top, greaterThan(id(2, 100)));
    expect(bar('Al-Baqarah, ayah'), findsOneWidget);

    // Saved a moment after scrolling stops.
    expect(h.prefs.getString(PrefsReadingStore.readingKey), isNull);
    await tester.pump(ReadingPositionController.saveDelay);
    expect(PrefsReadingStore(h.prefs).readingPosition()?.verseId, top);

    container = await restart(tester);
    expect(container.read(readingPositionProvider), top);
    expect(ayah(top), findsOneWidget);
  });

  testWidgets('going to the background saves at once', (tester) async {
    await launch(tester);
    openAt(tester, id(18, 10));
    await tester.pump();
    await tester.pump();
    expect(h.prefs.getString(PrefsReadingStore.readingKey), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(PrefsReadingStore(h.prefs).readingPosition()?.verseId, id(18, 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('a failed save is kept pending and retried', (tester) async {
    final failing = h.readingStore = FailingStore(PrefsReadingStore(h.prefs));
    final container = await launch(tester);
    container.read(readingPositionProvider.notifier).update(id(36, 1));
    expect(await container.read(readingPositionProvider.notifier).flush(), isFalse);
    failing.failing = false;
    expect(await container.read(readingPositionProvider.notifier).flush(), isTrue);
    expect(PrefsReadingStore(h.prefs).readingPosition()?.verseId, id(36, 1));
  });

  testWidgets('the surah index opens a surah at its header', (tester) async {
    final container = await launch(tester);
    await tapNav(tester, 'Surahs');
    await tester.enterText(find.byType(TextField), 'Kahf');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Al-Kahf'));
    await tester.pumpAndSettle();
    expect(container.read(readingPositionProvider), id(18, 1));
    expect(bar('Al-Kahf, ayah 1. Juz 15, page 293'), findsOneWidget);
  });

  testWidgets('tap an ayah: bookmark it, then remove it', (tester) async {
    final container = await launch(tester);
    tester.widget<AyahBlock>(ayah(3)).onTap!();
    await tester.pumpAndSettle();
    expect(tester.widget<AyahBlock>(ayah(3)).highlighted, isTrue, reason: 'the sheet acts on the marked ayah');
    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();
    expect(find.text('Bookmarked Al-Fatiha 1:3'), findsOneWidget);
    expect([for (final b in container.read(bookmarksProvider)) b.verseId], [3]);
    expect([for (final b in PrefsReadingStore(h.prefs).bookmarks()) b.verseId], [3]);
    expect(tester.widget<AyahBlock>(ayah(3)).highlighted, isFalse);

    tester.widget<AyahBlock>(ayah(3)).onTap!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove bookmark'));
    await tester.pumpAndSettle();
    expect(container.read(bookmarksProvider), isEmpty);
    expect(PrefsReadingStore(h.prefs).bookmarks(), isEmpty);
  });

  testWidgets('a bookmark that cannot be saved is not shown as saved', (tester) async {
    h.readingStore = FailingStore(PrefsReadingStore(h.prefs));
    final container = await launch(tester);
    tester.widget<AyahBlock>(ayah(3)).onTap!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save the bookmark. Try again.'), findsOneWidget);
    expect(container.read(bookmarksProvider), isEmpty);
  });

  testWidgets('copy puts the ayah and its reference on the clipboard', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await launch(tester);
    tester.widget<AyahBlock>(ayah(2)).onTap!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy the ayah'));
    await tester.pumpAndSettle();
    expect(copied.single, endsWith('— Al-Fatiha 1:2'));
    expect(copied.single, startsWith(quran.verse(2).uthmani));
  });

  testWidgets('the Taraweeh button opens Taraweeh mode, and back returns to the same place', (tester) async {
    h = await Harness.create(prefs: {'taraweeh_intro_seen': true});
    final container = await launch(tester);
    openAt(tester, id(2, 255));
    await tester.pump();
    await tester.pump();
    await tester.tap(taraweehButton);
    await tester.pumpAndSettle();
    expect(find.byType(ListenScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back to reading'));
    // Leaving stops the session, whose teardown awaits real futures.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.byType(ListenScreen), findsNothing);
    expect(container.read(readingPositionProvider), id(2, 255));
    expect(ayah(id(2, 255)), findsOneWidget);
  });

  testWidgets('search a reference: opens there and marks the ayah', (tester) async {
    final container = await launch(tester);
    await tester.tap(find.byTooltip('Search the Quran'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2:255');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Al-Baqarah 2:255'));
    await tester.pump();
    await tester.pump();
    expect(container.read(readingPositionProvider), id(2, 255));
    expect(tester.widget<AyahBlock>(ayah(id(2, 255))).highlighted, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<AyahBlock>(ayah(id(2, 255))).highlighted, isFalse, reason: 'the mark fades');
  });

  testWidgets('search Arabic words: results in mushaf order, tap one to read it', (tester) async {
    final container = await launch(tester);
    await tester.tap(find.byTooltip('Search the Quran'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'الحي القيوم');
    await tester.pumpAndSettle();
    // 2:255 and 3:2. (20:111 reads لِلْحَىِّ: "to the Living", a different word form.)
    expect(find.text('2 AYAHS'), findsOneWidget);
    await tester.tap(find.text('Al Imran 3:2'));
    await tester.pump();
    await tester.pump();
    expect(container.read(readingPositionProvider), id(3, 2));
  });

  testWidgets('search: too short, and nothing found, say so', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Search the Quran'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ق');
    await tester.pumpAndSettle();
    expect(find.text('Type at least 2 letters to search the text.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing found for “zzzz”.'), findsOneWidget);
  });

  testWidgets('go to a juz, then to a page', (tester) async {
    final container = await launch(tester);
    await tapNav(tester, 'Surahs');
    await tester.ensureVisible(find.text('Juz'));
    await tester.tap(find.text('Juz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Juz 2'));
    await tester.pumpAndSettle();
    expect(container.read(readingPositionProvider), id(2, 142));

    await tapNav(tester, 'Surahs');
    await tester.ensureVisible(find.text('Pages'));
    await tester.tap(find.text('Pages'));
    await tester.pumpAndSettle();
    // The list opens at the current page (22, juz 2's start).
    final pages =
        find.byWidget(tester.widget(find.ancestor(of: find.text('Page 22'), matching: find.byType(ListView))));
    await tester.dragUntilVisible(find.text('Page 42'), pages, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page 42'));
    await tester.pumpAndSettle();
    expect(container.read(readingPositionProvider), quran.pages.start(42));
    expect(bar('Al-Baqarah, ayah 253. Juz 3, page 42'), findsOneWidget);
  });

  testWidgets('the Bookmarks tab: continue reading, where Taraweeh ended, then bookmarks', (tester) async {
    h = await Harness.create(prefs: {
      PrefsReadingStore.bookmarksKey: '{"v":1,"items":[{"verse":${id(18, 10)},"at":"2026-11-04T18:00:00Z"},'
          '{"verse":${id(2, 255)},"at":"2026-11-02T18:00:00Z"}]}',
      PrefsReadingStore.taraweehKey: '{"v":1,"verse":${id(5, 81)},"at":"2026-11-03T21:00:00Z"}',
      PrefsReadingStore.readingKey: '{"v":1,"verse":${id(36, 1)},"at":"2026-11-04T08:00:00Z"}',
    });
    final container = await launch(tester);
    await tapNav(tester, 'Bookmarks');
    expect(find.text('CONTINUE READING'), findsOneWidget);
    expect(find.text('Ya-Sin 36:1'), findsOneWidget);
    expect(find.text('Where Taraweeh ended'), findsOneWidget);
    expect(find.text("Al-Ma'idah 5:81 · yesterday"), findsOneWidget);
    expect(find.text('2 BOOKMARKS'), findsOneWidget);
    // Newest first.
    expect(tester.getTopLeft(find.text('Al-Kahf 18:10')).dy,
        lessThan(tester.getTopLeft(find.text('Al-Baqarah 2:255')).dy));

    // Tap: read there, marked.
    await tester.tap(find.text('Al-Kahf 18:10'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(container.read(readingPositionProvider), id(18, 10));
    expect(tester.widget<AyahBlock>(ayah(id(18, 10))).highlighted, isTrue);
  });

  testWidgets('bookmarks: in Quran order, swipe to remove, undo puts it back as it was', (tester) async {
    h = await Harness.create(prefs: {
      PrefsReadingStore.bookmarksKey: '{"v":1,"items":[{"verse":${id(18, 10)},"at":"2026-11-04T18:00:00Z"},'
          '{"verse":${id(2, 255)},"at":"2026-11-02T18:00:00Z"}]}',
    });
    await launch(tester);
    await tapNav(tester, 'Bookmarks');
    await tester.tap(find.byTooltip('Sort bookmarks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In Quran order'));
    await tester.pumpAndSettle();
    expect(h.prefs.getBool('bookmarks_quran_order'), isTrue);
    expect(tester.getTopLeft(find.text('Al-Baqarah 2:255')).dy,
        lessThan(tester.getTopLeft(find.text('Al-Kahf 18:10')).dy));

    await tester.drag(find.text('Al-Kahf 18:10'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Al-Kahf 18:10'), findsNothing);
    expect([for (final b in PrefsReadingStore(h.prefs).bookmarks()) b.verseId], [id(2, 255)]);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final back = PrefsReadingStore(h.prefs).bookmarks();
    expect([for (final b in back) b.verseId], [id(18, 10), id(2, 255)]);
    expect(back.first.createdAt.toUtc(), DateTime.utc(2026, 11, 4, 18), reason: 'restored with its own date');
  });

  testWidgets('a removal that cannot be saved stays in the list', (tester) async {
    h = await Harness.create(prefs: {
      PrefsReadingStore.bookmarksKey: '{"v":1,"items":[{"verse":${id(18, 10)},"at":"2026-11-04T18:00:00Z"}]}',
    });
    h.readingStore = FailingStore(PrefsReadingStore(h.prefs));
    await launch(tester);
    await tapNav(tester, 'Bookmarks');
    await tester.drag(find.text('Al-Kahf 18:10'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Al-Kahf 18:10'), findsOneWidget);
    expect(find.text('Could not remove the bookmark. Try again.'), findsOneWidget);
  });

  testWidgets('press and hold an ayah: bookmarked at once, marked in the text, undo', (tester) async {
    final container = await launch(tester);
    final block = tester.widget<AyahBlock>(ayah(3));
    expect(block.bookmarked, isFalse);
    block.onLongPress!();
    await tester.pumpAndSettle();
    expect([for (final b in container.read(bookmarksProvider)) b.verseId], [3]);
    expect(tester.widget<AyahBlock>(ayah(3)).bookmarked, isTrue, reason: 'the ribbon shows in the text');
    expect(find.text('Bookmarked Al-Fatiha 1:3'), findsOneWidget);

    // Hold again: removed, with undo.
    tester.widget<AyahBlock>(ayah(3)).onLongPress!();
    await tester.pumpAndSettle();
    expect(container.read(bookmarksProvider), isEmpty);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect([for (final b in PrefsReadingStore(h.prefs).bookmarks()) b.verseId], [3]);
  });

  testWidgets('the surah name in the bar opens the Surahs tab; back returns to reading', (tester) async {
    await launch(tester);
    await tester.tap(bar('Al-Fatiha, ayah 1'));
    await tester.pumpAndSettle();
    expect(find.byType(QuranIndex), findsOneWidget);
    await tester.binding.handlePopRoute(); // the system back gesture
    await tester.pumpAndSettle();
    expect(find.byType(QuranIndex), findsNothing);
    expect(find.byType(ReaderScreen), findsOneWidget);
  });

  testWidgets('the scrubber flies through the pages', (tester) async {
    final container = await launch(tester);
    // It shows once the text moves.
    await tester.drag(find.byType(QuranView), const Offset(0, -100));
    await tester.pump();
    final strip = find.descendant(of: find.byType(PageScrubber), matching: find.byType(GestureDetector));
    final rect = tester.getRect(strip);
    await tester.dragFrom(rect.topCenter + const Offset(0, 30), Offset(0, rect.height * 0.5));
    await tester.pumpAndSettle();
    final page = quran.pageOf(container.read(readingPositionProvider));
    expect(page, inInclusiveRange(250, 350), reason: 'about halfway through 604 pages');
  });

  testWidgets('More: the khatm planner, settings, and what is coming', (tester) async {
    await launch(tester);
    await tapNav(tester, 'More');
    expect(find.text('COMING SOON'), findsOneWidget);
    for (final soon in ['Recitation audio', 'Translations', 'Tafsir']) {
      expect(find.text(soon), findsOneWidget);
    }
    expect(find.text('Khatm planner'), findsOneWidget, reason: 'working now, above Settings');
    expect(find.text('Notes'), findsNothing, reason: 'notes live in the ayah sheet and Bookmarks');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Quran text size'), findsOneWidget);
  });

  group('page view', () {
    /// The ayah spans of the page on screen, by verse id.
    Map<int, TextSpan> pageSpans(WidgetTester tester) {
      final spans = <int, TextSpan>{};
      final quran = loadQuran();
      for (final rich in tester.widgetList<RichText>(find.descendant(
        of: find.byType(MushafPageView),
        matching: find.byType(RichText),
      ))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.recognizer != null) {
            final text = span.text ?? '';
            for (var id = 1; id <= 6236; id++) {
              if (text.startsWith(displayAyahText(quran.verse(id).uthmani).trimRight())) {
                spans[id] = span;
                break;
              }
            }
          }
          return true;
        });
      }
      return spans;
    }

    testWidgets('the bar switches to pages at the same place, and back', (tester) async {
      final container = await launch(tester);
      openAt(tester, id(2, 255));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Read page by page'));
      await tester.pumpAndSettle();
      expect(find.byType(MushafPageView), findsOneWidget);
      expect(h.prefs.getString('reading_layout'), 'pages');
      // The page 2:255 is on; the reading position becomes where it starts.
      expect(find.text('٤٢'), findsOneWidget);
      expect(container.read(readingPositionProvider), lessThanOrEqualTo(id(2, 255)));
      expect(quran.pageOf(container.read(readingPositionProvider)), 42);

      await tester.tap(find.byTooltip('Read as one scroll'));
      await tester.pumpAndSettle();
      expect(find.byType(QuranView), findsOneWidget);
      expect(quran.pageOf(container.read(readingPositionProvider)), 42);
    });

    testWidgets('swiping left to right turns to the next page, as a mushaf does', (tester) async {
      h = await Harness.create(prefs: {'reading_layout': 'pages'});
      final container = await launch(tester);
      expect(find.text('١'), findsOneWidget); // page 1
      await tester.fling(find.byType(MushafPageView), const Offset(200, 0), 800);
      await tester.pumpAndSettle();
      expect(container.read(readingPositionProvider), quran.pages.start(2));
      expect(find.text('٢'), findsOneWidget);
      await tester.pump(ReadingPositionController.saveDelay);
      expect(PrefsReadingStore(h.prefs).readingPosition()?.verseId, quran.pages.start(2));
    });

    testWidgets('an ayah on the page opens its sheet; a search lands on its page, marked', (tester) async {
      h = await Harness.create(prefs: {'reading_layout': 'pages'});
      final container = await launch(tester);
      (pageSpans(tester)[3]!.recognizer! as TapGestureRecognizer).onTap!();
      await tester.pumpAndSettle();
      expect(find.text('Bookmark'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search the Quran'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '18:10');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Al-Kahf 18:10'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(quran.pageOf(container.read(readingPositionProvider)), quran.pageOf(id(18, 10)));
      expect(pageSpans(tester)[id(18, 10)]!.style?.backgroundColor, isNotNull);
    });

    testWidgets('press and hold an ayah on the page: bookmarked, with a ribbon in the text', (tester) async {
      h = await Harness.create(prefs: {'reading_layout': 'pages'});
      final container = await launch(tester);
      final firstWords = displayAyahText(quran.verse(2).uthmani).trim();
      final paragraph = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains(firstWords));
      await tester.longPressAt(tester.getCenter(paragraph));
      await tester.pumpAndSettle();
      final saved = [for (final b in container.read(bookmarksProvider)) b.verseId];
      expect(saved, hasLength(1));
      expect(quran.pageOf(saved.single), 1);
      expect(
        find.descendant(of: find.byType(MushafPageView), matching: find.byIcon(Icons.bookmark)),
        findsOneWidget,
      );
    });

    testWidgets('the layout is kept after a restart', (tester) async {
      h = await Harness.create(prefs: {'reading_layout': 'pages'});
      await launch(tester);
      expect(find.byType(MushafPageView), findsOneWidget);
      await restart(tester);
      expect(find.byType(MushafPageView), findsOneWidget);
    });
  });

  group('share', () {
    Future<void> openShare(WidgetTester tester, int verseId) async {
      tester.widget<AyahBlock>(ayah(verseId)).onTap!();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Share'));
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(find.text('Share the ayah'), findsOneWidget);
      expect(find.byType(AyahCard), findsOneWidget);
    }

    testWidgets('as text: the ayah and its reference', (tester) async {
      await launch(tester);
      await openShare(tester, 2);
      await tester.ensureVisible(find.text('Share as text'));
      await tester.tap(find.text('Share as text'));
      await tester.pumpAndSettle();
      expect(h.sharer.texts.single, startsWith(quran.verse(2).uthmani));
      expect(h.sharer.texts.single, endsWith('— Al-Fatiha 1:2'));
      expect(find.text('Share the ayah'), findsNothing, reason: 'the sheet closes once shared');
    });

    testWidgets('as an image: the card rendered at 3x, named after the ayah', (tester) async {
      await launch(tester);
      await openShare(tester, 2);
      await tester.ensureVisible(find.text('Share as an image'));
      // Rendering to an image is real work the fake clock does not drive.
      await tester.runAsync(() async {
        await tester.tap(find.text('Share as an image'));
        for (var i = 0; i < 20 && h.sharer.images.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pumpAndSettle();
      final image = h.sharer.images.single;
      expect(image.fileName, 'rafiq-1-2.png');
      expect(image.text, 'Al-Fatiha 1:2');
      expect(image.bytes, greaterThan(1000));
    });
  });
}
