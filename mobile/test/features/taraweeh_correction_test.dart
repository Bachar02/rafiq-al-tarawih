import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/data/taraweeh_ledger.dart';
import 'package:rafiq/features/listen/listen_screen.dart';
import 'package:rafiq/features/quran_view/quran_view.dart';
import 'package:rafiq/features/reader/reader_screen.dart';

import '../support/app_nav.dart';
import '../support/fakes.dart';

/// Where Taraweeh stopped, on screen (PLAN.md §39): shown in Bookmarks,
/// corrected afterwards from the reader's ayah sheet, saved when the app
/// leaves, and tonight's hint. Never asked during prayer.
void main() {
  final quran = loadQuran();
  int id(int s, int a) => quran.verseId(s, a)!;
  late Harness h;

  /// A ledger: Taraweeh last night (2026-11-03) from 5:60 to [to].
  Map<String, Object> lastNight({int to = 81, int from = 60}) {
    var ledger = TaraweehLedger.empty;
    var at = DateTime(2026, 11, 3, 21);
    for (var a = from; a <= to; a++) {
      ledger = ledger.observe(id(5, a), at);
      at = at.add(const Duration(seconds: 30));
    }
    return {PrefsReadingStore.taraweehLedgerKey: jsonEncode(ledger.toJson())};
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> launch(WidgetTester tester, Map<String, Object> prefs) async {
    h = await Harness.create(prefs: {'taraweeh_intro_seen': true, ...prefs});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
  }

  Finder ayah(int verseId) => find.descendant(
        of: find.byType(QuranView),
        matching: find.byWidgetPredicate((w) => w is AyahBlock && w.verse.id == verseId),
      );

  Future<void> tapAyah(WidgetTester tester, int verseId) async {
    tester.widget<AyahBlock>(ayah(verseId)).onTap!();
    await settle(tester);
  }

  testWidgets('Bookmarks: where Taraweeh ended, from the ledger; a tap opens it', (tester) async {
    await launch(tester, lastNight());
    await tapNav(tester, 'Bookmarks');
    expect(find.text('Where Taraweeh ended'), findsOneWidget);
    expect(find.text("Al-Ma'idah 5:81 · yesterday"), findsOneWidget);
    await tester.tap(find.text("Al-Ma'idah 5:81 · yesterday"));
    await settle(tester);
    expect(ayah(id(5, 81)), findsOneWidget);
  });

  testWidgets('Bookmarks: heard, but too little to say: it says so, and opens the last ayah heard', (tester) async {
    await launch(tester, lastNight(from: 80, to: 81)); // two ayahs: weak
    await tapNav(tester, 'Bookmarks');
    expect(find.text('Not clear from what was heard. Tap an ayah to set it.'), findsOneWidget);
    await tester.tap(find.text('Not clear from what was heard. Tap an ayah to set it.'));
    await settle(tester);
    expect(ayah(id(5, 81)), findsOneWidget);
  });

  testWidgets('no Taraweeh ever followed: no tile, and the reader offers nothing about it', (tester) async {
    await launch(tester, const {});
    await tapNav(tester, 'Bookmarks');
    expect(find.text('Where Taraweeh ended'), findsNothing);
    await tapNav(tester, 'Read');
    tester.state<ReaderScreenState>(find.byType(ReaderScreen)).openAt(id(5, 83), mark: false);
    await settle(tester);
    await tapAyah(tester, id(5, 83));
    expect(find.text('Taraweeh ended here'), findsNothing);
  });

  testWidgets('the reader: "Taraweeh ended here" corrects the night, saved at once, with Undo', (tester) async {
    final container = await launch(tester, lastNight());
    // Where it already stopped: nothing to correct.
    tester.state<ReaderScreenState>(find.byType(ReaderScreen)).openAt(id(5, 81), mark: false);
    await settle(tester);
    await tapAyah(tester, id(5, 81));
    expect(find.text('Taraweeh ended here'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    tester.state<ReaderScreenState>(find.byType(ReaderScreen)).openAt(id(5, 83), mark: false);
    await settle(tester);

    await tapAyah(tester, id(5, 83));
    await tester.ensureVisible(find.text('Taraweeh ended here'));
    await settle(tester);
    await tester.tap(find.text('Taraweeh ended here'));
    await settle(tester);
    expect(find.text("Taraweeh ended at Al-Ma'idah 5:83"), findsOneWidget);
    expect(container.read(taraweehPositionProvider)?.verseId, id(5, 83));
    expect(container.read(taraweehPositionProvider)?.fixedBy, FixSource.user);
    expect(PrefsReadingStore(h.prefs).taraweehLedger()?.progress(quran)?.verseId, id(5, 83));
    expect(container.read(taraweehLedgerProvider).nights.single.key, '2026-11-03', reason: 'last night corrected');

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(container.read(taraweehPositionProvider)?.verseId, id(5, 81));
    expect(PrefsReadingStore(h.prefs).taraweehLedger()?.progress(quran)?.verseId, id(5, 81));
  });

  testWidgets('tonight: the hint from last night, and the app going to the background saves the night', (tester) async {
    await launch(tester, lastNight());
    await tester.tap(taraweehButton);
    await settle(tester);
    // 5:82 begins juz 7: the ayah after where it stopped decides.
    expect(h.engine.startedWith, const JuzHint(7));
    expect(find.text("Last night ended at Al-Ma'idah 5:81."), findsOneWidget);

    h.now = DateTime(2026, 11, 4, 21);
    h.engine.emit(const EngineReady());
    for (var a = 82; a <= 90; a++) {
      h.engine.emit(heard(at(5, a)));
    }
    await settle(tester);
    expect(PrefsReadingStore(h.prefs).taraweehLedger()?.nights, hasLength(1), reason: 'tonight not saved yet');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    final saved = PrefsReadingStore(h.prefs).taraweehLedger()!;
    expect(saved.nights.map((n) => n.key), ['2026-11-03', '2026-11-04']);
    expect(saved.progress(quran)?.verseId, id(5, 90));
    expect(find.byType(ListenScreen), findsOneWidget, reason: 'nothing asked, nothing shown');
  });

  testWidgets('French and Arabic', (tester) async {
    await launch(tester, {...lastNight(from: 80, to: 81), 'language': 'fr'});
    await tapNav(tester, 'Signets');
    expect(find.textContaining('Pas clair'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await launch(tester, {...lastNight(), 'language': 'ar'});
    tester.state<ReaderScreenState>(find.byType(ReaderScreen)).openAt(id(5, 83), mark: false);
    await settle(tester);
    await tapAyah(tester, id(5, 83));
    await tester.ensureVisible(find.text('انتهت التراويح هنا'));
    await settle(tester);
    await tester.tap(find.text('انتهت التراويح هنا'));
    await settle(tester);
    expect(find.textContaining('انتهت التراويح عند'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
