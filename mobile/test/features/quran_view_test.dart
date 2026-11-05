import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/app/theme.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/data/quran.dart';
import 'package:rafiq/features/quran_view/book_index.dart';
import 'package:rafiq/features/quran_view/book_items.dart';
import 'package:rafiq/features/quran_view/quran_view.dart';
import 'package:rafiq/l10n/l10n.dart';

import '../support/fakes.dart';

/// Verse ids of the ayahs built now, in item order.
List<int> builtVerses(WidgetTester tester) =>
    [for (final b in tester.widgetList<AyahBlock>(find.byType(AyahBlock))) b.verse.id];

AyahBlock block(WidgetTester tester, int verseId) =>
    tester.widget<AyahBlock>(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == verseId));

/// The top of built ayah [verseId] on screen (logical pixels).
double topOf(WidgetTester tester, int verseId) =>
    tester.getTopLeft(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == verseId)).dy;

void main() {
  final quran = loadQuran();
  final names = loadSurahNames();
  final en = lookupAppLocalizations(const Locale('en'));
  int id(int s, int a) => quran.verseId(s, a)!;

  group('BookIndex', () {
    final book = BookIndex(quran);

    test('6,236 ayahs and 114 headers, in reading order', () {
      expect(book.length, 6350);
      expect(book.at(0), isA<SurahHeaderItem>());
      expect((book.at(1) as AyahItem).verse.id, 1);
      expect((book.at(8) as SurahHeaderItem).surah.index, 2);
      expect((book.at(9) as AyahItem).verse.id, id(2, 1));
      expect((book.at(book.length - 1) as AyahItem).verse.id, Quran.verseCount);
      expect(() => book.at(book.length), throwsRangeError);
    });

    test('verse and surah indexes round-trip for the whole Quran', () {
      for (var v = 1; v <= Quran.verseCount; v++) {
        final i = book.ofVerse(v);
        expect((book.at(i) as AyahItem).verse.id, v);
        expect(book.verseAt(i), v);
      }
      for (var s = 1; s <= Quran.surahCount; s++) {
        final i = book.ofSurah(s);
        expect((book.at(i) as SurahHeaderItem).surah.index, s);
        expect(book.surahAt(i), s);
        expect(book.verseAt(i), quran.surah(s).firstVerseId, reason: 'a header stands for ayah 1');
      }
    });
  });

  group('DivisionMark labels', () {
    test('juz, hizb quarter and page starts', () {
      expect(DivisionMark.labelFor(quran, 1, en), isNull);
      expect(DivisionMark.labelFor(quran, id(2, 142), en), 'Juz 2 · Page 22');
      expect(DivisionMark.labelFor(quran, id(2, 26), en), '¼ Hizb 1');
      expect(DivisionMark.labelFor(quran, id(2, 6), en), 'Page 3');
      expect(DivisionMark.labelFor(quran, id(2, 7), en), isNull);
      expect(DivisionMark.hizbLabel(en, 5), 'Hizb 2');
      expect(DivisionMark.hizbLabel(en, 240), '¾ Hizb 60');
    });
  });

  group('QuranView', () {
    Future<QuranViewController> pumpView(
      WidgetTester tester, {
      int initialVerse = 1,
      double textScale = 1,
      bool live = false,
      Position? current,
      int? followVerse,
      ValueChanged<int>? onTop,
      ValueChanged<bool>? onAway,
      ValueChanged<Verse>? onTap,
      QuranViewController? controller,
    }) async {
      final c = controller ?? QuranViewController();
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(
          body: QuranView(
            quran: quran,
            names: names,
            initialVerse: initialVerse,
            controller: c,
            textScale: textScale,
            live: live,
            current: current,
            followVerse: followVerse,
            onTopVerseChanged: onTop,
            onAwayChanged: onAway,
            onAyahTap: onTap,
          ),
        ),
      ));
      await tester.pump();
      return c;
    }

    testWidgets('builds only what is on screen, even in Al-Baqarah', (tester) async {
      await pumpView(tester, initialVerse: id(2, 1));
      final built = builtVerses(tester);
      expect(built, contains(id(2, 1)));
      expect(built.length, lessThan(40), reason: 'virtualized: not all 286 ayahs');
      expect(find.byType(SurahHeader), findsOneWidget);
    });

    testWidgets('opens at a verse and reports it as the top', (tester) async {
      final tops = <int>[];
      await pumpView(tester, initialVerse: id(2, 255), onTop: tops.add);
      await tester.pump();
      expect(tops.last, id(2, 255));
      expect(topOf(tester, id(2, 255)), closeTo(RubricSpace.quranTop, 1));
    });

    testWidgets('jumps anywhere and scrolls across surahs', (tester) async {
      final tops = <int>[];
      final c = await pumpView(tester, onTop: tops.add);
      c.jumpToVerse(id(77, 45));
      await tester.pump();
      await tester.pump();
      expect(c.topVerse, id(77, 45));
      // Drag on through the end of al-Mursalat into an-Naba'.
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(QuranView), const Offset(0, -500));
        await tester.pump();
      }
      expect(c.topVerse, greaterThan(id(77, 50)));
      expect(quran.verse(c.topVerse!).surah, 78);
      // And back up across the boundary.
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(QuranView), const Offset(0, 500));
        await tester.pump();
      }
      expect(quran.verse(c.topVerse!).surah, 77);

      c.jumpToSurah(114);
      await tester.pump();
      await tester.pump();
      expect(c.topVerse, id(114, 1));
      expect(find.byWidgetPredicate((w) => w is SurahHeader && w.surah.index == 114), findsOneWidget);
      c.jumpToVerse(1);
      await tester.pump();
      await tester.pump();
      expect(builtVerses(tester).first, 1);
      expect(c.topVerse, 1);
    });

    testWidgets('reaches both ends of the Quran without overscrolling into nothing', (tester) async {
      final c = await pumpView(tester);
      await tester.drag(find.byType(QuranView), const Offset(0, 800));
      await tester.pumpAndSettle();
      expect(c.topVerse, 1);
      c.jumpToVerse(id(114, 1));
      await tester.pump();
      await tester.drag(find.byType(QuranView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == Quran.verseCount), findsOneWidget);
    });

    testWidgets('the largest text size keeps the top ayah', (tester) async {
      final c = QuranViewController();
      await pumpView(tester, initialVerse: id(2, 100), controller: c);
      await tester.pump();
      await pumpView(tester, initialVerse: id(2, 100), controller: c, textScale: AppSettingsScale.max);
      await tester.pump();
      await tester.pump();
      expect(c.topVerse, id(2, 100));
      expect(block(tester, id(2, 100)).fontSize, closeTo(26 * AppSettingsScale.max, 0.01));
    });

    testWidgets('reading tone everywhere; taps reach the caller', (tester) async {
      final tapped = <int>[];
      await pumpView(tester, initialVerse: id(93, 1), onTap: (v) => tapped.add(v.id));
      expect(tester.widgetList<AyahBlock>(find.byType(AyahBlock)).every((b) => b.tone == AyahTone.reading), isTrue);
      block(tester, id(93, 3)).onTap!();
      expect(tapped, [id(93, 3)]);
    });

    testWidgets('live: recited, current and coming ayahs in the imam\'s surah only', (tester) async {
      await pumpView(tester, live: true, current: pos(93, 10), followVerse: id(93, 10));
      await tester.pump();
      expect(block(tester, id(93, 9)).tone, AyahTone.recited);
      expect(block(tester, id(93, 10)).tone, AyahTone.current);
      expect(block(tester, id(93, 11)).tone, AyahTone.upcoming);
      // The next surah is not "recited" just because it comes later in the book.
      await tester.drag(find.byType(QuranView), const Offset(0, -500));
      await tester.pump();
      expect(block(tester, id(94, 1)).tone, AyahTone.upcoming);
    });

    testWidgets('follows: the current ayah sits in the comfort zone, far moves are cuts', (tester) async {
      final c = QuranViewController();
      await pumpView(tester, live: true, current: pos(2, 10), followVerse: id(2, 10), controller: c);
      await tester.pump();
      final height = tester.getSize(find.byType(QuranView)).height;
      expect(topOf(tester, id(2, 10)) / height, closeTo(0.38, 0.03));

      // An ayah below the comfort zone is brought back to about 38%.
      await pumpView(tester, live: true, current: pos(2, 11), followVerse: id(2, 11), controller: c);
      await tester.pumpAndSettle();
      expect(topOf(tester, id(2, 11)) / height, closeTo(0.38, 0.03));

      // Short ayahs: the next one is in the comfort zone already, nothing moves.
      await pumpView(tester, live: true, current: pos(112, 1), followVerse: id(112, 1), controller: c);
      await tester.pumpAndSettle();
      final before = topOf(tester, id(112, 2));
      expect(before / height, inInclusiveRange(0.25, 0.6));
      await pumpView(tester, live: true, current: pos(112, 2), followVerse: id(112, 2), controller: c);
      await tester.pumpAndSettle();
      expect(topOf(tester, id(112, 2)), closeTo(before, 0.5));

      // Far away (another surah): one cut, not a scroll through the text.
      await pumpView(tester, live: true, current: pos(18, 10), followVerse: id(18, 10), controller: c);
      await tester.pump();
      await tester.pump();
      expect(topOf(tester, id(18, 10)) / height, closeTo(0.38, 0.03));
    });

    testWidgets('a hand scroll detaches; out of view it reports away; return re-attaches', (tester) async {
      final away = <bool>[];
      final c = QuranViewController();
      await pumpView(tester, live: true, current: pos(2, 10), followVerse: id(2, 10), onAway: away.add, controller: c);
      await tester.pump();
      await tester.drag(find.byType(QuranView), const Offset(0, -2500));
      await tester.pumpAndSettle();
      expect(away, [true]);

      // While detached, the imam moving on does not pull the text back.
      await pumpView(tester, live: true, current: pos(2, 11), followVerse: id(2, 11), onAway: away.add, controller: c);
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == id(2, 11)).hitTestable(), findsNothing);

      await c.returnToFollow();
      await tester.pumpAndSettle();
      expect(away, [true, false]);
      final height = tester.getSize(find.byType(QuranView)).height;
      expect(topOf(tester, id(2, 11)) / height, closeTo(0.38, 0.03));
    });

    testWidgets('a parent rebuild with the same inputs does not rebuild the text', (tester) async {
      await pumpView(tester, initialVerse: id(2, 1));
      final first = tester.element(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == id(2, 3)));
      final widgetBefore = first.widget;
      await pumpView(tester, initialVerse: id(2, 1));
      final after = tester.element(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == id(2, 3)));
      expect(identical(after.widget, widgetBefore), isTrue);
    });
  });
}

/// Mirrors AppSettings' bounds without importing settings into the view tests.
abstract final class AppSettingsScale {
  static const max = 1.6;
}
