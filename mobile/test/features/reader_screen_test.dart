import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/listen/listen_screen.dart';
import 'package:rafiq/features/quran_view/quran_view.dart';
import 'package:rafiq/features/reader/reader_screen.dart';
import 'package:rafiq/features/reader/reading_position.dart';

import '../support/fakes.dart';

/// A store whose writes fail (a full disk): reads still work.
class FailingStore implements ReadingStore {
  FailingStore(this._inner);
  final ReadingStore _inner;
  bool failing = true;

  @override
  SavedPosition? readingPosition() => _inner.readingPosition();
  @override
  Future<bool> saveReadingPosition(SavedPosition p) async => !failing && await _inner.saveReadingPosition(p);
  @override
  SavedPosition? taraweehPosition() => _inner.taraweehPosition();
  @override
  Future<bool> saveTaraweehPosition(SavedPosition p) async => !failing && await _inner.saveTaraweehPosition(p);
  @override
  List<Bookmark> bookmarks() => _inner.bookmarks();
  @override
  Future<bool> saveBookmarks(List<Bookmark> b) async => !failing && await _inner.saveBookmarks(b);
}

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
  Finder ayah(int verseId) => find.descendant(
        of: find.byType(QuranView),
        matching: find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == verseId),
      );

  testWidgets('first run opens at Al-Fatiha, in the reader', (tester) async {
    final container = await launch(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.byType(ListenScreen), findsNothing);
    expect(container.read(readingPositionProvider), 1);
    expect(find.text('Al-Fatiha · Juz 1 · Page 1'), findsOneWidget);
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
    expect(find.textContaining('Al-Baqarah · Juz'), findsOneWidget);

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
    await tester.tap(find.byTooltip('Surahs, juz and bookmarks'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Kahf');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Al-Kahf'));
    await tester.pumpAndSettle();
    expect(container.read(readingPositionProvider), id(18, 1));
    expect(find.text('Al-Kahf · Juz 15 · Page 293'), findsOneWidget);
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
    final container = await launch(tester);
    openAt(tester, id(2, 255));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Taraweeh: follow the imam'));
    await tester.pumpAndSettle();
    expect(find.byType(ListenScreen), findsOneWidget);
    await tester.binding.handlePopRoute(); // the system back gesture
    await tester.pumpAndSettle();
    expect(find.byType(ListenScreen), findsNothing);
    expect(container.read(readingPositionProvider), id(2, 255));
    expect(ayah(id(2, 255)), findsOneWidget);
  });
}
