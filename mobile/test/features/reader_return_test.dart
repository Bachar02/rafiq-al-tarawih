import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/navigation.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/data/khatm.dart';
import 'package:rafiq/data/note.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/khatm/khatm_screen.dart';
import 'package:rafiq/features/navigate/navigate_screen.dart';
import 'package:rafiq/features/reader/reader_screen.dart';
import 'package:rafiq/features/search/search_screen.dart';

import '../support/app_nav.dart';
import '../support/fakes.dart';

/// The way back after a jump into the reader: a "Back to …" button, and the
/// phone's back button doing the same.
void main() {
  final quran = loadQuran();
  int id(int s, int a) => quran.verseId(s, a)!;
  late Harness h;

  final note = Note(
    verseId: id(2, 255),
    text: 'Read after every prayer',
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 3),
  );
  final notesPrefs = {
    PrefsReadingStore.notesKey: jsonEncode({
      'v': 1,
      'items': [note.toJson()],
    }),
  };

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

  Future<void> openNoteFromNotes(WidgetTester tester) async {
    await tapNav(tester, 'Bookmarks');
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(note.text));
    await tester.pumpAndSettle();
  }

  Finder backButton(String label) => find.widgetWithText(OutlinedButton, label);

  testWidgets('a note opens the reader with "Back to notes", which returns to the notes', (tester) async {
    final container = await launch(tester, prefs: notesPrefs);
    await openNoteFromNotes(tester);
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(container.read(readingPositionProvider), id(2, 255));
    expect(backButton('Back to notes'), findsOneWidget);

    await tester.tap(backButton('Back to notes'));
    await tester.pumpAndSettle();
    expect(container.read(homeTabProvider), HomeTab.bookmarks);
    expect(find.text(note.text), findsOneWidget, reason: 'the Notes view, not Bookmarks');
    expect(container.read(readingPositionProvider), 1, reason: 'only a look: the reading place is kept');

    // Back in the reader by the tab bar: no way back any more.
    await tapNav(tester, 'Read');
    expect(backButton('Back to notes'), findsNothing);
  });

  testWidgets("the phone's back button goes back to the notes too", (tester) async {
    final container = await launch(tester, prefs: notesPrefs);
    await openNoteFromNotes(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(container.read(homeTabProvider), HomeTab.bookmarks);
    expect(find.text(note.text), findsOneWidget);
    // Back again: the reader, as before.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(container.read(homeTabProvider), HomeTab.read);
    expect(container.read(readerReturnProvider), isNull);
  });

  testWidgets('after reading on from the note, going back keeps the new place', (tester) async {
    final container = await launch(tester, prefs: notesPrefs);
    await openNoteFromNotes(tester);
    container.read(readingPositionProvider.notifier).update(quran.pages.start(43));
    await tester.pumpAndSettle();
    await tester.tap(backButton('Back to notes'));
    await tester.pumpAndSettle();
    expect(container.read(readingPositionProvider), quran.pages.start(43));
  });

  testWidgets('leaving the Read tab ends the way back', (tester) async {
    final container = await launch(tester, prefs: notesPrefs);
    await openNoteFromNotes(tester);
    await tapNav(tester, 'More');
    expect(container.read(readerReturnProvider), isNull);
    await tapNav(tester, 'Read');
    expect(backButton('Back to notes'), findsNothing);
  });

  testWidgets('a bookmark opens the reader with "Back to bookmarks"', (tester) async {
    final container = await launch(tester, prefs: {
      PrefsReadingStore.bookmarksKey: '{"v":1,"items":[{"verse":${id(18, 10)},"at":"2026-11-04T18:00:00Z"}]}',
    });
    await tapNav(tester, 'Bookmarks');
    await tester.tap(find.text('Al-Kahf 18:10'));
    await tester.pumpAndSettle();
    await tester.tap(backButton('Back to bookmarks'));
    await tester.pumpAndSettle();
    expect(container.read(homeTabProvider), HomeTab.bookmarks);
    expect(find.text('Al-Kahf 18:10'), findsOneWidget);
  });

  testWidgets('a search result opens the reader with "Back to search", which keeps the search', (tester) async {
    final container = await launch(tester);
    await tester.tap(find.byTooltip('Search the Quran'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2:255');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Al-Baqarah 2:255'));
    await tester.pumpAndSettle();
    expect(container.read(readingPositionProvider), id(2, 255));

    await tester.tap(backButton('Back to search'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '2:255');
    expect(find.text('Al-Baqarah 2:255'), findsOneWidget, reason: 'the results are still there');
    expect(container.read(readingPositionProvider), 1);

    // Closing the search: back where the user started, with no way back left.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
    expect(backButton('Back to search'), findsNothing);
  });

  testWidgets('the Surahs tab: "Back to surahs"', (tester) async {
    final container = await launch(tester);
    await tapNav(tester, 'Surahs');
    await tester.ensureVisible(find.text('Juz'));
    await tester.tap(find.text('Juz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Juz 2'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(container.read(homeTabProvider), HomeTab.surahs);
    expect(find.byType(QuranIndex), findsOneWidget);
  });

  testWidgets('the khatm planner: "Back to the khatm" reopens it over the tab it came from', (tester) async {
    final plan = KhatmPlan(startedOn: DateTime(2026, 11, 1), endsOn: DateTime(2026, 11, 30), startPage: 1)
        .reading(DateTime(2026, 11, 1), [for (var p = 1; p <= 10; p++) p]);
    final container = await launch(tester, prefs: {
      PrefsReadingStore.khatmKey: jsonEncode(KhatmBook(active: plan, finished: const []).toJson()),
    });
    await tapNav(tester, 'More');
    await tester.tap(find.text('Khatm planner'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue khatm (page 11)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue khatm (page 11)'));
    await tester.pumpAndSettle();
    expect(find.byType(KhatmScreen), findsNothing);

    await tester.tap(backButton('Back to the khatm'));
    await tester.pumpAndSettle();
    expect(find.byType(KhatmScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(container.read(homeTabProvider), HomeTab.more);
  });

  testWidgets('in Arabic and French, the button says where it goes', (tester) async {
    for (final (lang, label) in [('ar', 'العودة إلى الملاحظات'), ('fr', 'Retour aux notes')]) {
      await launch(tester, prefs: {...notesPrefs, 'language': lang});
      await tapNav(tester, lang == 'ar' ? 'العلامات' : 'Signets');
      await tester.tap(find.text(lang == 'ar' ? 'الملاحظات' : 'Notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(note.text));
      await tester.pumpAndSettle();
      expect(backButton(label), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
