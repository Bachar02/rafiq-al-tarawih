import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/data/note.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/notes/note_sheet.dart';
import 'package:rafiq/features/notes/notes_controller.dart';
import 'package:rafiq/features/quran_view/quran_view.dart';
import 'package:rafiq/features/reader/reader_screen.dart';

import '../support/fakes.dart';

/// Stored notes, as the store writes them.
Map<String, Object> notesPrefs(List<Note> notes) => {
      PrefsReadingStore.notesKey: jsonEncode({
        'v': 1,
        'items': [for (final n in notes) n.toJson()],
      }),
    };

void main() {
  group('NotesController', () {
    late Harness h;
    late ProviderContainer c;
    NotesController notes() => c.read(notesProvider.notifier);
    List<Note> saved() => PrefsReadingStore(h.prefs).notes();

    setUp(() async {
      h = await Harness.create();
      c = h.container();
      addTearDown(c.dispose);
    });

    test('save, then edit: one note per ayah, created date kept, newest edit first', () async {
      expect(await notes().save(10, '  first thought  '), isTrue);
      final created = h.now;
      h.now = h.now.add(const Duration(hours: 1));
      await notes().save(20, 'another');
      h.now = h.now.add(const Duration(hours: 1));
      await notes().save(10, 'second thought');
      expect([for (final n in c.read(notesProvider)) n.verseId], [10, 20]);
      final note = notes().noteFor(10)!;
      expect(note.text, 'second thought');
      expect(note.createdAt, created);
      expect(note.updatedAt, h.now);
      expect(saved(), c.read(notesProvider));
    });

    test('saving the same text changes nothing, not even the date', () async {
      await notes().save(10, 'same');
      final before = notes().noteFor(10);
      h.now = h.now.add(const Duration(days: 1));
      await notes().save(10, ' same ');
      expect(notes().noteFor(10), before);
    });

    test('an empty text deletes the note', () async {
      await notes().save(10, 'x');
      expect(await notes().save(10, '   \n'), isTrue);
      expect(c.read(notesProvider), isEmpty);
      expect(saved(), isEmpty);
    });

    test('the text is kept to 2000 characters', () async {
      await notes().save(10, 'a' * 2100);
      expect(notes().noteFor(10)!.text.length, Note.maxLength);
    });

    test('Undo restores a deleted note with its dates and place', () async {
      await notes().save(10, 'older');
      h.now = h.now.add(const Duration(hours: 1));
      await notes().save(20, 'middle');
      h.now = h.now.add(const Duration(hours: 1));
      await notes().save(30, 'newer');
      final middle = notes().noteFor(20)!;
      await notes().delete(20);
      expect(await notes().restore(middle), isTrue);
      expect([for (final n in c.read(notesProvider)) n.verseId], [30, 20, 10]);
      expect(notes().noteFor(20), middle);
    });

    test('a failed save is reported and nothing changes', () async {
      final failing = FailingStore(PrefsReadingStore(h.prefs))..failing = false;
      h.readingStore = failing;
      c = h.container();
      addTearDown(c.dispose);
      await notes().save(10, 'kept');
      failing.failing = true;
      expect(await notes().save(10, 'lost?'), isFalse);
      expect(await notes().save(20, 'new'), isFalse);
      expect(await notes().delete(10), isFalse);
      expect([for (final n in c.read(notesProvider)) n.text], ['kept']);
    });
  });

  test('a note is shown in the direction it is written', () {
    expect(noteDirection('بسم الله'), TextDirection.rtl);
    expect(noteDirection('Remember this on Friday'), TextDirection.ltr);
    expect(noteDirection('À relire avec la famille'), TextDirection.ltr);
    expect(noteDirection('   '), isNull);
  });

  group('notes from the reader', () {
    late Harness h;

    Future<ProviderContainer> start(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
      await tester.pump();
      await tester.pump();
      return ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
    }

    Future<ProviderContainer> launch(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
      h = await Harness.create(prefs: prefs);
      return start(tester);
    }

    Future<void> openNoteSheet(WidgetTester tester, int verseId, String button) async {
      tester
          .widget<AyahBlock>(find.descendant(
            of: find.byType(QuranView),
            matching: find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == verseId),
          ))
          .onTap!();
      await tester.pumpAndSettle();
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
    }

    testWidgets('add a note from the ayah sheet', (tester) async {
      final container = await launch(tester);
      await openNoteSheet(tester, 3, 'Add a note');
      expect(find.text('Note on Al-Fatiha 1:3'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull,
          reason: 'nothing to save yet');
      expect(find.text('Delete note'), findsNothing);
      await tester.enterText(find.byType(TextField), 'The Most Merciful');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Note saved'), findsOneWidget);
      expect(PrefsReadingStore(h.prefs).notes().single.text, 'The Most Merciful');
      expect(container.read(notesProvider).single.verseId, 3);
    });

    testWidgets('edit shows the note in its own direction; delete can be undone', (tester) async {
      final note =
          Note(verseId: 3, text: 'الرحمن الرحيم', createdAt: DateTime(2026, 11, 1), updatedAt: DateTime(2026, 11, 2));
      final container = await launch(tester, prefs: notesPrefs([note]));
      await openNoteSheet(tester, 3, 'Edit note');
      expect(find.text('الرحمن الرحيم'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).textDirection, TextDirection.rtl);
      await tester.enterText(find.byType(TextField), 'In English now');
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).textDirection, TextDirection.ltr);

      await tester.tap(find.text('Delete note'));
      await tester.pumpAndSettle();
      expect(find.text('Note deleted'), findsOneWidget);
      expect(PrefsReadingStore(h.prefs).notes(), isEmpty);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(container.read(notesProvider).single, note, reason: 'back as it was, dates and all');
      expect(PrefsReadingStore(h.prefs).notes().single, note);
    });

    testWidgets('saving an emptied note deletes it', (tester) async {
      final note = Note(verseId: 3, text: 'x', createdAt: DateTime(2026, 11, 1), updatedAt: DateTime(2026, 11, 1));
      final container = await launch(tester, prefs: notesPrefs([note]));
      await openNoteSheet(tester, 3, 'Edit note');
      await tester.enterText(find.byType(TextField), '  ');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Note deleted'), findsOneWidget);
      expect(container.read(notesProvider), isEmpty);
    });

    testWidgets('a note that cannot be saved stays in the sheet, with the text', (tester) async {
      h = await Harness.create();
      h.readingStore = FailingStore(PrefsReadingStore(h.prefs));
      final container = await start(tester);
      await openNoteSheet(tester, 3, 'Add a note');
      await tester.enterText(find.byType(TextField), 'Do not lose me');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save the note. Your text is still here.'), findsOneWidget);
      expect(find.text('Do not lose me'), findsOneWidget);
      expect(container.read(notesProvider), isEmpty);
    });

    testWidgets('the field stops at 2000 characters', (tester) async {
      await launch(tester);
      await openNoteSheet(tester, 2, 'Add a note');
      await tester.enterText(find.byType(TextField), 'b' * 2100);
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text.length, Note.maxLength);
    });
  });
}
