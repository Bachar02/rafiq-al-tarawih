import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/data/quran.dart';
import 'package:rafiq/data/settings.dart';
import 'package:rafiq/data/study_text.dart';
import 'package:rafiq/features/study/study_screen.dart';

import '../support/app_nav.dart';
import '../support/fakes.dart';

void main() {
  final catalog = loadStudyCatalog();
  StudySource source(String key) => catalog.byKey(key)!;

  group('the bundled texts', () {
    test('are the four chosen, each with its publisher and version', () {
      expect([for (final s in catalog.sources) s.key],
          ['english_saheeh', 'french_hameedullah', 'arabic_moyassar', 'french_mokhtasar']);
      for (final s in catalog.sources) {
        for (final ui in ['en', 'fr', 'ar']) {
          expect(s.name(ui), isNotEmpty);
          expect(s.credit(ui), isNotEmpty);
        }
        expect(s.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
        expect(s.url, 'https://quranenc.com/en/browse/${s.key}');
      }
      expect(source('arabic_moyassar').direction, TextDirection.rtl);
      expect(source('english_saheeh').direction, TextDirection.ltr);
    });

    test('are complete and read as published', () async {
      for (final s in catalog.sources) {
        final text = await loadStudyTextFile(s);
        expect(text.key, s.key);
        expect(text.version, s.version);
        for (var id = 1; id <= Quran.verseCount; id++) {
          expect(text.ayah(id).text.trim(), isNotEmpty, reason: '${s.key} $id');
        }
      }
      // Anchors from QuranEnc's pages, so a text swapped for another fails.
      final saheeh = await loadStudyTextFile(source('english_saheeh'));
      expect(saheeh.ayah(1).text, startsWith('(1) In the name of Allāh,[2] the Entirely Merciful'));
      expect(saheeh.ayah(1).footnotes, startsWith('[2]- Allāh is a proper name'));
      final hamidullah = await loadStudyTextFile(source('french_hameedullah'));
      expect(hamidullah.ayah(1).text, 'Au nom d’Allah, le Tout Miséricordieux, le Très Miséricordieux.[1]');
      final muyassar = await loadStudyTextFile(source('arabic_moyassar'));
      expect(muyassar.ayah(1).text, startsWith('أبتدئ قراءة القرآن باسم الله مستعينا به'));
    });

    test('a text that is not the one asked for, or not complete, is refused', () {
      String body(String key, int count, {String text = 'x'}) => jsonEncode({
            'key': key,
            'version': '1.0.0',
            'ayahs': List.filled(count, [text, ''])
          });
      expect(StudyText.parse((raw: body('a', 6236), key: 'a')).ayah(6236).text, 'x');
      expect(() => StudyText.parse((raw: body('b', 6236), key: 'a')), throwsFormatException);
      expect(() => StudyText.parse((raw: body('a', 6235), key: 'a')), throwsFormatException);
      expect(() => StudyText.parse((raw: body('a', 6236, text: ' '), key: 'a')), throwsFormatException);
    });
  });

  group('which text is shown', () {
    String? pick(StudyKind kind, String ui, [String? chosen]) =>
        catalog.pick(kind, languageCode: ui, chosen: chosen)?.key;

    test('one in the interface language, else English (translation) or Arabic (tafsir)', () {
      expect(pick(StudyKind.translation, 'en'), 'english_saheeh');
      expect(pick(StudyKind.translation, 'fr'), 'french_hameedullah');
      expect(pick(StudyKind.translation, 'ar'), 'english_saheeh');
      expect(pick(StudyKind.tafsir, 'en'), 'arabic_moyassar');
      expect(pick(StudyKind.tafsir, 'fr'), 'french_mokhtasar');
      expect(pick(StudyKind.tafsir, 'ar'), 'arabic_moyassar');
    });

    test('the user\'s choice, while it is bundled and of the right kind', () {
      expect(pick(StudyKind.tafsir, 'en', 'french_mokhtasar'), 'french_mokhtasar');
      expect(pick(StudyKind.tafsir, 'en', 'english_saheeh'), 'arabic_moyassar', reason: 'not a tafsir');
      expect(pick(StudyKind.translation, 'fr', 'english_gone'), 'french_hameedullah', reason: 'no longer bundled');
      expect(StudyCatalog.empty.pick(StudyKind.tafsir, languageCode: 'en'), isNull);
    });

    test('the choice is saved, and nothing is saved before one is made', () async {
      final h = await Harness.create();
      final store = SettingsStore(h.prefs);
      await store.save(store.load());
      expect(h.prefs.getString('translation_key'), isNull);
      await store.save(store.load().copyWith(tafsirKey: 'french_mokhtasar'));
      expect(store.load().tafsirKey, 'french_mokhtasar');
      expect(store.load().translationKey, isNull);
    });
  });

  group('the study view', () {
    late Harness h;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> launch(WidgetTester tester, [Map<String, Object> prefs = const {}]) async {
      h = await Harness.create(prefs: {'taraweeh_intro_seen': true, ...prefs});
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
      await settle(tester);
    }

    /// Tap ayah [id] in the reader, then [action] in its sheet.
    Future<void> fromAyahSheet(WidgetTester tester, int id, String action) async {
      tester.widget<AyahBlock>(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == id)).onTap!();
      await settle(tester);
      await tester.ensureVisible(find.text(action));
      await settle(tester);
      await tester.tap(find.text(action));
      await settle(tester);
    }

    Future<String> textOf(String key, int id) async => (await loadStudyTextFile(source(key))).ayah(id).text.trim();

    testWidgets('the ayah sheet opens the translation, credited, and Tafsir switches to the tafsir', (tester) async {
      await launch(tester);
      await fromAyahSheet(tester, 2, 'Translation');
      expect(find.byType(StudyScreen), findsOneWidget);
      expect(find.text('Al-Fatiha 1:2'), findsOneWidget);
      expect(find.text(await textOf('english_saheeh', 2)), findsOneWidget);
      expect(find.text('Saheeh International'), findsOneWidget);
      expect(find.text('Noor International Center · version 1.1.2 · QuranEnc.com'), findsOneWidget);
      expect(find.textContaining('it is not the Quran itself'), findsOneWidget);

      await tester.tap(find.text('Tafsir'));
      await settle(tester);
      expect(find.text(await textOf('arabic_moyassar', 2)), findsOneWidget);
      expect(find.text('In Arabic'), findsOneWidget, reason: 'no English tafsir: the Arabic one says so');
      expect(find.text('King Fahd Glorious Quran Printing Complex · version 1.0.0 · QuranEnc.com'), findsOneWidget);
      expect(find.textContaining('it is not the Quran itself'), findsNothing);
    });

    testWidgets('next and previous move by one ayah, across surahs, without moving the reader', (tester) async {
      await launch(tester);
      await fromAyahSheet(tester, 2, 'Tafsir');
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Next ayah'));
        await settle(tester);
      }
      expect(find.text('Al-Fatiha 1:7'), findsOneWidget);
      await tester.tap(find.text('Next ayah'));
      await settle(tester);
      expect(find.text('Al-Baqarah 2:1'), findsOneWidget);
      expect(find.text(await textOf('arabic_moyassar', 8)), findsOneWidget);
      await tester.tap(find.text('Previous ayah'));
      await settle(tester);
      expect(find.text('Al-Fatiha 1:7'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.byType(StudyScreen)));
      await tester.pageBack();
      await settle(tester);
      expect(container.read(readingPositionProvider), 1, reason: 'the reader stays where it was');
    });

    testWidgets('the first ayah has no Previous', (tester) async {
      await launch(tester);
      await fromAyahSheet(tester, 1, 'Translation');
      expect(
          tester
              .widget<TextButton>(find.ancestor(of: find.text('Previous ayah'), matching: find.byType(TextButton)))
              .onPressed,
          isNull);
    });

    testWidgets('choosing another tafsir is shown at once and remembered', (tester) async {
      await launch(tester);
      await fromAyahSheet(tester, 2, 'Tafsir');
      await tester.tap(find.byTooltip('Choose the text'));
      await settle(tester);
      expect(find.text('Choose a tafsir'), findsOneWidget);
      await tester.tap(find.text('Al-Mukhtasar (French)'));
      await settle(tester);
      expect(find.text(await textOf('french_mokhtasar', 2)), findsOneWidget);
      expect(find.text('In French'), findsOneWidget);
      expect(h.prefs.getString('tafsir_key'), 'french_mokhtasar');
    });

    testWidgets('in French: Hamidullah and the French Mukhtasar, with no language label', (tester) async {
      await launch(tester, {'language': 'fr'});
      await fromAyahSheet(tester, 2, 'Traduction');
      expect(find.text(await textOf('french_hameedullah', 2)), findsOneWidget);
      expect(find.textContaining('Muhammad Hamidullah · version 1.0.2'), findsOneWidget);
      await tester.tap(find.text('Tafsir').last);
      await settle(tester);
      expect(find.text(await textOf('french_mokhtasar', 2)), findsOneWidget);
      expect(find.textContaining('En '), findsNothing);
    });

    testWidgets('in Arabic: Al-Muyassar, and the English translation says it is English', (tester) async {
      await launch(tester, {'language': 'ar'});
      await fromAyahSheet(tester, 2, 'تفسير');
      expect(find.text(await textOf('arabic_moyassar', 2)), findsOneWidget);
      expect(find.text('التفسير الميسر'), findsOneWidget);
      await tester.tap(find.text('ترجمة').last);
      await settle(tester);
      expect(find.text(await textOf('english_saheeh', 2)), findsOneWidget);
      expect(find.text('باللغة الإنجليزية'), findsOneWidget);
      // The English text keeps its own direction inside the Arabic interface.
      final text = find.text(await textOf('english_saheeh', 2));
      expect(Directionality.of(tester.element(text)), TextDirection.ltr);
    });

    testWidgets('a text that cannot be opened says so', (tester) async {
      await launch(tester);
      h.studyTexts = (_) => Future.error(const FormatException('damaged'));
      await fromAyahSheet(tester, 2, 'Translation');
      expect(find.textContaining('could not be opened'), findsOneWidget);
    });

    testWidgets('More opens it at the reading position; Settings shows and changes the choice', (tester) async {
      await launch(tester);
      await tapNav(tester, 'More');
      await tester.tap(find.text('Translation and tafsir'));
      await settle(tester);
      expect(find.text('Al-Fatiha 1:1'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      await openSettings(tester);
      expect(find.text('Saheeh International'), findsOneWidget);
      expect(find.text('At-Tafsir Al-Muyassar'), findsOneWidget);
      await tester.ensureVisible(find.text('At-Tafsir Al-Muyassar')); // below the reminders
      await settle(tester);
      await tester.tap(find.text('At-Tafsir Al-Muyassar'));
      await settle(tester);
      await tester.tap(find.text('Al-Mukhtasar (French)'));
      await settle(tester);
      expect(find.text('Al-Mukhtasar (French)'), findsOneWidget);
      expect(h.prefs.getString('tafsir_key'), 'french_mokhtasar');
    });

    testWidgets('a slow text shows progress, then the text', (tester) async {
      await launch(tester);
      final gate = Completer<void>();
      h.studyTexts = (s) async {
        await gate.future;
        return loadStudyTextFile(s);
      };
      await fromAyahSheet(tester, 2, 'Translation');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(find.text(await textOf('english_saheeh', 2)), findsOneWidget);
    });
  });
}
