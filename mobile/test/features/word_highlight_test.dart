import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/app/theme.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/core/text/quran_display.dart';
import 'package:rafiq/core/text/word_map.dart';
import 'package:rafiq/features/listen/listen_controller.dart';
import 'package:rafiq/features/listen/listen_state.dart';
import 'package:rafiq/features/listen/taraweeh_position.dart';
import 'package:rafiq/features/listen/word_highlight.dart';
import 'package:rafiq/l10n/l10n.dart';

import '../support/fakes.dart';

/// Word highlighting (developer setting, off by default; PLAN.md §33).
void main() {
  final quran = loadQuran();

  /// A final naming word [index] of surah:ayah.
  Heard said(int surah, int ayah, int index, {int asrMs = 100, TrackStatus status = TrackStatus.tracking}) => Heard(
        text: 'نص',
        start: 0,
        end: 1,
        asrMs: asrMs,
        state: at(surah, ayah, status: status),
        isFinal: true,
        word: HeardWord(verseId: pos(surah, ayah).verseId, index: index),
      );

  group('the session', () {
    late Harness h;
    late ProviderContainer container;
    ListenController controller() => container.read(listenControllerProvider.notifier);
    ListenState state() => container.read(listenControllerProvider);
    int? piece() => highlightedPiece(
          state(),
          enabled: container.read(settingsProvider).wordHighlight,
          quran: quran,
          words: DisplayWordMap(),
          now: DateTime.now(),
          staleAfter: const Duration(milliseconds: 1500),
        );

    Future<void> session({required bool on}) async {
      h = await Harness.create(prefs: {'word_highlight': on});
      container = h.container();
      await controller().start();
      h.engine.emit(const EngineReady());
    }

    tearDown(() => container.dispose());

    test('off by default: nothing is highlighted, whatever the engine says', () async {
      h = await Harness.create();
      container = h.container();
      expect(container.read(settingsProvider).wordHighlight, isFalse);
      await controller().start();
      h.engine.emit(const EngineReady());
      h.engine.emit(said(2, 21, 2));
      expect(state().liveWord, isNull);
      expect(piece(), isNull);
      expect(state().track.position, pos(2, 21), reason: 'the ayah follows as always');
    });

    test('on: the word the engine names is marked, in Uthmani pieces (يا ايها is one)', () async {
      await session(on: true);
      h.engine.emit(said(2, 21, 1));
      expect(piece(), 0, reason: 'Simple Clean ايها is in the first Uthmani word');
      h.engine.emit(said(2, 21, 2));
      expect(piece(), 1);
    });

    test('a result without a word (the word tracker is not sure) hides it at once', () async {
      await session(on: true);
      h.engine.emit(said(2, 21, 2));
      expect(piece(), 1);
      h.engine.emit(heard(at(2, 21)));
      expect(state().liveWord, isNull);
      expect(piece(), isNull);
    });

    test('the ayah engine unsure: hidden, even with a word', () async {
      await session(on: true);
      h.engine.emit(said(2, 21, 2, status: TrackStatus.uncertain));
      expect(piece(), isNull);
    });

    test('a word outside the ayah on screen is not marked (al-Fatiha excursion, a jump)', () async {
      await session(on: true);
      h.engine.emit(said(18, 3, 1));
      expect(piece(), isNotNull);
      // Al-Fatiha at a new rakʿah: the screen stays on the imam's surah.
      h.engine.emit(said(1, 2, 1));
      expect(state().inFatihaExcursion, isTrue);
      expect(piece(), isNull);
    });

    test('stopping, or the app going to the background, hides it', () async {
      await session(on: true);
      h.engine.emit(said(2, 21, 2));
      await controller().pause();
      expect(state().liveWord, isNull);
      expect(piece(), isNull);
    });

    testWidgets('a stale word goes on its own, even if no result comes again', (tester) async {
      // testWidgets runs on a fake clock: its timers move with tester.pump.
      await session(on: true);
      h.engine.emit(said(2, 21, 2, asrMs: 300));
      expect(state().liveWord, isNotNull);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(state().liveWord, isNotNull, reason: 'fresh for 1.5 s from when its audio was heard');
      await tester.pump(const Duration(milliseconds: 200));
      expect(state().liveWord, isNull, reason: 'gone 1.5 s after (1.2 s after arriving, 0.3 s transcribing)');
      // The Taraweeh ledger saves what was heard a few seconds later.
      await tester.pump(TaraweehProgressController.saveDelay);
    });

    test('the threshold is a developer setting', () async {
      h = await Harness.create(prefs: {'word_highlight': true, 'word_stale_seconds': 3.0});
      container = h.container();
      expect(container.read(settingsProvider).wordStaleSeconds, 3.0);
    });
  });

  test('stale by the clock: hidden even before the timer runs', () {
    final now = DateTime(2026, 11, 12, 21);
    final s = ListenState(
      phase: SessionPhase.listening,
      track: at(2, 21),
      lastSure: pos(2, 21),
      liveWord: LiveWord(HeardWord(verseId: pos(2, 21).verseId, index: 2), now.subtract(const Duration(seconds: 2))),
    );
    int? shown(Duration stale) =>
        highlightedPiece(s, enabled: true, quran: quran, words: DisplayWordMap(), now: now, staleAfter: stale);
    expect(shown(const Duration(milliseconds: 1500)), isNull);
    expect(shown(const Duration(seconds: 3)), 1);
    expect(
        highlightedPiece(s,
            enabled: false, quran: quran, words: DisplayWordMap(), now: now, staleAfter: const Duration(seconds: 3)),
        isNull);
  });

  group('the reader', () {
    final verse = quran.verse(pos(2, 21).verseId);

    /// The span AyahBlock built (Text.rich puts it under one carrying the style).
    TextSpan built(RichText r) => (r.text as TextSpan).children!.single as TextSpan;

    Future<RichText> pump(WidgetTester tester, {required AyahTone tone, int? word, bool unsure = false}) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.dark(),
        home: Scaffold(body: AyahBlock(verse: verse, tone: tone, currentWord: word, unsure: unsure)),
      ));
      await tester.pumpAndSettle();
      return tester.widget<RichText>(find.byType(RichText).first);
    }

    final expected = '${displayAyahText(verse.uthmani)}${ayahEndMarker(verse.ayah)}';

    testWidgets('the marked word changes colour, and nothing else: same text, same font', (tester) async {
      final plain = await pump(tester, tone: AyahTone.current);
      final marked = await pump(tester, tone: AyahTone.current, word: 1);
      expect(plain.text.toPlainText(), expected);
      expect(marked.text.toPlainText(), expected, reason: 'the same characters: same shaping and line breaks');
      expect(marked.text.style, plain.text.style);
      final rubric = AppTheme.dark().extension<RafiqColors>()!.rubric;
      final spans = built(marked).children!.cast<TextSpan>();
      final colored = [
        for (final (i, s) in spans.indexed)
          if (s.style?.color == rubric) i
      ];
      expect(colored, [1, spans.length - 1], reason: 'the word, and the end marker as before');
    });

    testWidgets('without a word the ayah is built exactly as before', (tester) async {
      final plain = await pump(tester, tone: AyahTone.current);
      final span = built(plain);
      expect(span.text, displayAyahText(verse.uthmani));
      expect(span.children, hasLength(1));
    });

    testWidgets('not marked when unsure, or on any ayah but the current one', (tester) async {
      for (final (tone, unsure) in [(AyahTone.current, true), (AyahTone.recited, false), (AyahTone.reading, false)]) {
        final r = await pump(tester, tone: tone, word: 1, unsure: unsure);
        expect(built(r).text, displayAyahText(verse.uthmani), reason: '$tone unsure=$unsure');
      }
    });
  });
}
