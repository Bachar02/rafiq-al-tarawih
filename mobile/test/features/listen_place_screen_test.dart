import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/data/surah_names.dart';
import 'package:rafiq/features/listen/listen_screen.dart';
import 'package:rafiq/features/listen/listen_state.dart';
import 'package:rafiq/features/listen/widgets/place_choices.dart';
import 'package:rafiq/features/quran_view/quran_view.dart';

import '../support/app_nav.dart';
import '../support/fakes.dart';

/// Repeated words on the Taraweeh screen (PLAN.md §38): the status line says
/// what is happening, a few quiet buttons offer what the user can do, and
/// every one of them goes through an existing action.
void main() {
  late Harness h;
  final names = loadSurahNames();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> launch(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    Size size = const Size(1080, 2340),
  }) async {
    h = await Harness.create(prefs: {'taraweeh_intro_seen': true, ...prefs});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await tester.pump();
    await tester.tap(taraweehButton);
    await settle(tester);
    h.engine.emit(const EngineReady());
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(ListenScreen)));
  }

  Future<void> hear(WidgetTester tester, TrackState state, {bool isFinal = true}) async {
    h.engine.emit(heard(state, isFinal: isFinal));
    await settle(tester);
  }

  /// The choice buttons, by their words.
  Finder choice(String label) => find.descendant(of: find.byType(PlaceChoices), matching: find.text(label));
  Finder anyChoice() => find.descendant(of: find.byType(PlaceChoices), matching: find.byType(OutlinedButton));

  /// The header region scrolls (large text, the test font): reveal, then tap.
  Future<void> tapChoice(WidgetTester tester, String label) async {
    await tester.ensureVisible(choice(label));
    await settle(tester);
    await tester.tap(choice(label));
    await settle(tester);
  }

  List<int> currentAyahs(WidgetTester tester) => [
        for (final b in tester.widgetList<AyahBlock>(find.byType(AyahBlock)))
          if (b.tone == AyahTone.current) b.verse.id,
      ];

  Set<int> readerSurahs(WidgetTester tester) => {
        for (final b in tester
            .widgetList<AyahBlock>(find.descendant(of: find.byType(QuranView), matching: find.byType(AyahBlock))))
          b.verse.surah,
      };

  final kahf = tie([(18, 89), (18, 92)]);
  final refrain = tie([
    for (final a in [13, 16, 18, 21, 23]) (55, a)
  ]);
  final threeSurahs = tie([(3, 50), (26, 108), (26, 110), (43, 63)]);

  testWidgets('one surah, two copies: named, nothing marked, one button per ayah, confirmed in the sheet',
      (tester) async {
    await launch(tester);
    await hear(tester, kahf);

    expect(find.text('Repeated words'), findsOneWidget);
    expect(find.text('These words repeat in Al-Kahf. Waiting for more words to tell which ayah.'), findsOneWidget);
    expect(find.bySemanticsLabel('Surah Al-Kahf, ayah not yet known'), findsOneWidget);
    expect(find.text('—'), findsOneWidget, reason: 'no ayah number');
    expect(find.text('LAST SURE'), findsNothing, reason: 'nothing was ever sure');
    expect(find.text('AYAH'), findsOneWidget);
    expect(readerSurahs(tester), {18});
    expect(currentAyahs(tester), isEmpty, reason: 'no ayah highlighted as confirmed');
    expect(choice('Ayah 89'), findsOneWidget);
    expect(choice('Ayah 92'), findsOneWidget);
    expect(choice('Stay on Al-Kahf'), findsOneWidget);

    // A button opens the existing ayah sheet; nothing changes until confirmed.
    await tapChoice(tester, 'Ayah 92');
    expect(find.text('Al-Kahf · ayah 92'), findsOneWidget);
    expect(h.engine.positions, isEmpty);
    await tester.tap(find.text('The imam is here'));
    await settle(tester);
    expect(h.engine.positions, [pos(18, 92).verseId]);
    expect(find.bySemanticsLabel('Surah Al-Kahf, ayah 92'), findsOneWidget);
    expect(currentAyahs(tester), [pos(18, 92).verseId]);
    expect(anyChoice(), findsNothing, reason: 'the stale choices are gone');
    expect(find.text('Repeated words'), findsNothing);
  });

  testWidgets('dismissing the sheet changes nothing', (tester) async {
    final container = await launch(tester);
    await hear(tester, kahf);
    await tapChoice(tester, 'Ayah 89');
    await tester.tapAt(const Offset(10, 10)); // the scrim
    await settle(tester);
    expect(h.engine.positions, isEmpty);
    expect(container.read(listenControllerProvider).place, isA<InSurah>());
  });

  testWidgets('many copies: no wall of buttons; the ayah is chosen in the text', (tester) async {
    final container = await launch(tester);
    await hear(tester, refrain);
    expect(anyChoice(), findsNWidgets(2));
    expect(choice('Ayah 13'), findsNothing);
    await tapChoice(tester, 'Choose the ayah in the text');
    final state = container.read(listenControllerProvider);
    expect(state.browsing, isTrue);
    expect(state.readerSurah, 55);
    expect(readerSurahs(tester), contains(55));
    // The first copy is at the top. Then the existing correction: tap the
    // ayah, "the imam is here".
    tester
        .widget<AyahBlock>(find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == pos(55, 13).verseId))
        .onTap!();
    await settle(tester);
    await tester.tap(find.text('The imam is here'));
    await settle(tester);
    expect(h.engine.positions, [pos(55, 13).verseId]);
    expect(container.read(listenControllerProvider).browsing, isFalse);
  });

  testWidgets('"Stay on" the surah: the lock, with Undo; not offered once there', (tester) async {
    await launch(tester);
    await hear(tester, refrain);
    await tapChoice(tester, 'Stay on Ar-Rahman');
    expect(h.engine.locks.last, const SurahRange(55, 56));
    expect(find.text('Staying on Ar-Rahman, then the next surah'), findsOneWidget);
    expect(choice('Stay on Ar-Rahman'), findsNothing);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(h.engine.locks.last, isNull);
    expect(choice('Stay on Ar-Rahman'), findsOneWidget);
  });

  testWidgets('a held ayah stays: the surah is only a possibility', (tester) async {
    await launch(tester);
    await hear(tester, at(93, 3));
    await hear(tester, tie([(55, 13), (55, 16)], position: pos(93, 3)));
    expect(find.bySemanticsLabel('Surah Ad-Duha, ayah 3, not sure'), findsOneWidget);
    expect(find.text('LAST SURE'), findsOneWidget);
    expect(find.textContaining('These words repeat in Ar-Rahman.'), findsOneWidget);
    expect(find.textContaining('Holding the last sure ayah.'), findsOneWidget);
    expect(currentAyahs(tester), [pos(93, 3).verseId], reason: 'the reader is not jumped');
    expect(readerSurahs(tester), {93});
    expect(choice('Ayah 13'), findsOneWidget);
  });

  testWidgets('across surahs: one choice per surah, localized names, no raw references', (tester) async {
    final container = await launch(tester);
    await hear(tester, threeSurahs);
    expect(find.text('Repeated words'), findsOneWidget);
    expect(
        find.text('These words are in more than one surah. Waiting for more words, or choose below.'), findsOneWidget);
    expect(find.bySemanticsLabel('No position yet'), findsOneWidget);
    expect(choice('${names.of(3)} · ayah 50'), findsOneWidget);
    expect(choice('Stay on ${names.of(26)}'), findsOneWidget);
    expect(choice('${names.of(43)} · ayah 63'), findsOneWidget);
    expect(find.textContaining('3:50'), findsNothing);
    expect(find.textContaining('26:108'), findsNothing);

    // A surah with several copies: the lock narrows the choice at once.
    await tapChoice(tester, 'Stay on ${names.of(26)}');
    expect(h.engine.locks.last, const SurahRange(26, 27));
    expect(container.read(listenControllerProvider).place, isA<InSurah>());
    expect(choice('Ayah 108'), findsOneWidget);
    expect(choice('Ayah 110'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(choice('${names.of(3)} · ayah 50'), findsOneWidget);

    // A surah with one copy: that ayah, through the sheet.
    await tapChoice(tester, '${names.of(43)} · ayah 63');
    await tester.tap(find.text('The imam is here'));
    await settle(tester);
    expect(h.engine.positions, [pos(43, 63).verseId]);
    expect(h.engine.locks.last, isNull, reason: 'undone above: no lock to move');
    expect(find.bySemanticsLabel('Surah ${names.of(43)}, ayah 63'), findsOneWidget);
  });

  testWidgets('nothing offered for an untrusted tie, more than three surahs, or a basmala', (tester) async {
    await launch(tester);
    for (final state in [
      tie([(18, 89), (18, 92)], trusted: false),
      tie([(3, 50), (26, 108), (43, 63), (71, 3)]),
      tie([(1, 1), (27, 30)]),
    ]) {
      await hear(tester, state);
      expect(anyChoice(), findsNothing);
      expect(find.text('Repeated words'), findsNothing);
      expect(find.text('Listening for the imam'), findsOneWidget);
      expect(find.bySemanticsLabel('No position yet'), findsOneWidget);
    }
  });

  testWidgets('a miss keeps the choices; the next confirmed ayah takes their place', (tester) async {
    await launch(tester);
    await hear(tester, kahf);
    await hear(tester, tie([(18, 89), (18, 92)], evidence: false, status: TrackStatus.idle));
    expect(choice('Ayah 89'), findsOneWidget);
    await hear(tester, at(18, 93));
    expect(anyChoice(), findsNothing);
    expect(find.text('Following the imam'), findsOneWidget);
    expect(currentAyahs(tester), [pos(18, 93).verseId]);
  });

  testWidgets('French', (tester) async {
    await launch(tester, prefs: {'language': 'fr'});
    await hear(tester, kahf);
    final kahfFr = loadSurahNames().inLanguage(NameLanguage.fr).of(18);
    expect(find.text('Mots répétés'), findsOneWidget);
    expect(find.textContaining('dans la sourate $kahfFr'), findsOneWidget);
    expect(choice('Verset 89'), findsOneWidget);
    expect(choice('Rester sur $kahfFr'), findsOneWidget);
    await hear(tester, refrain);
    expect(choice('Choisir le verset dans le texte'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic: right to left, Arabic names, nothing overflows', (tester) async {
    await launch(tester, prefs: {'language': 'ar'});
    await hear(tester, threeSurahs);
    final choices = find.byType(PlaceChoices);
    expect(Directionality.of(tester.element(choices)), TextDirection.rtl);
    expect(find.text('كلمات متكررة'), findsOneWidget);
    expect(choice('آل عمران · الآية 50'), findsOneWidget);
    expect(choice('البقاء في الشعراء'), findsOneWidget);
    // The choices start on the right, under the status line's words.
    final width = tester.getSize(find.byType(ListenScreen)).width;
    for (final label in ['آل عمران · الآية 50', 'الزخرف · الآية 63']) {
      expect(tester.getRect(choice(label)).right, greaterThan(width * 0.75), reason: label);
    }
    await hear(tester, kahf);
    expect(find.textContaining('في سورة الكهف'), findsOneWidget);
    expect(choice('الآية 89'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('200% system text on a small phone: the choices wrap and nothing overflows', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, size: const Size(320 * 3, 568 * 3));
    await hear(tester, threeSurahs);
    expect(tester.takeException(), isNull);
    await hear(tester, at(93, 3));
    await hear(tester, tie([(18, 89), (18, 92)], position: pos(93, 3)));
    expect(tester.takeException(), isNull);
    expect(anyChoice(), findsNWidgets(3));
  });
}
