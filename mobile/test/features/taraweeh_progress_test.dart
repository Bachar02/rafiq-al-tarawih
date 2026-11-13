import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/core/engine/matcher.dart';
import 'package:rafiq/core/engine/tracker.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/data/taraweeh_ledger.dart';
import 'package:rafiq/features/listen/taraweeh_position.dart';

import '../support/fakes.dart';

/// Where Taraweeh stopped, through the listening session (PLAN.md §39): what
/// reaches the ledger, when it is saved, and whole SIMULATED nights through
/// the real tracker, with the Quran's own text standing in for perfect
/// recognition. Real recorded recognition: `taraweeh_replay_test.dart`.
void main() {
  late Harness h;
  late ProviderContainer container;
  final quran = loadQuran();
  int v(int surah, int ayah) => quran.verseId(surah, ayah)!;

  Future<void> listening() async {
    await container.read(listenControllerProvider.notifier).start();
    h.engine.emit(const EngineReady());
  }

  TaraweehLedger ledger() => container.read(taraweehLedgerProvider);
  int? progress() => container.read(taraweehPositionProvider)?.verseId;

  setUp(() async {
    h = await Harness.create();
    h.now = DateTime(2027, 2, 9, 21);
    container = h.container();
  });
  tearDown(() => container.dispose());

  group('what reaches the ledger', () {
    test('committed finals only: no preview, no doubt, no miss, no prediction', () async {
      await listening();
      h.engine.emit(heard(at(2, 142), isFinal: false)); // a preview
      h.engine.emit(heard(at(2, 143, status: TrackStatus.uncertain))); // doubt
      h.engine.emit(heard(at(2, 144, evidence: false))); // a miss holding a position
      expect(ledger().nights, isEmpty);
      // `upcoming` (the ayah predicted next) is not where the imam is.
      h.engine.emit(heard(at(2, 145, upcoming: pos(2, 146))));
      expect(ledger().nights.single.runs.single.last, v(2, 145));
    });

    test('Al-Fatiha never; "the imam is here" yes', () async {
      await listening();
      for (var a = 1; a <= 7; a++) {
        h.engine.emit(heard(at(1, a)));
      }
      expect(ledger().nights, isEmpty);
      container.read(listenControllerProvider.notifier).setPosition(pos(18, 1));
      expect(ledger().nights.single.runs.single.first, v(18, 1));
    });

    test('nothing is asked: the session never waits on the ledger', () async {
      await listening();
      for (var a = 1; a <= 20; a++) {
        h.engine.emit(heard(at(36, a)));
      }
      expect(container.read(listenControllerProvider).displayed, pos(36, 20));
      expect(progress(), v(36, 20));
    });
  });

  group('saving', () {
    test('a few seconds after a change, without leaving: a killed app loses little', () async {
      await listening();
      for (var a = 10; a <= 14; a++) {
        h.engine.emit(heard(at(3, a)));
      }
      expect(PrefsReadingStore(h.prefs).taraweehLedger(), isNull, reason: 'not yet');
      await Future<void>.delayed(TaraweehProgressController.saveDelay + const Duration(milliseconds: 200));
      final saved = PrefsReadingStore(h.prefs).taraweehLedger()!;
      expect(saved.progress(quran)?.verseId, v(3, 14));
      // The process dies here: a new one reads the same night.
      final restarted = h.container();
      expect(restarted.read(taraweehPositionProvider)?.verseId, v(3, 14));
      restarted.dispose();
    });

    test('flushed at once when asked (leaving the mode, the background)', () async {
      await listening();
      for (var a = 10; a <= 14; a++) {
        h.engine.emit(heard(at(3, a)));
      }
      expect(await container.read(taraweehLedgerProvider.notifier).flush(), isTrue);
      expect(PrefsReadingStore(h.prefs).taraweehLedger()?.progress(quran)?.verseId, v(3, 14));
    });

    test('a correction is saved at once; Undo restores and saves', () async {
      final controller = container.read(taraweehLedgerProvider.notifier);
      final before = controller.correct(v(5, 81), h.now);
      await pumpEventQueue();
      expect(PrefsReadingStore(h.prefs).taraweehLedger()?.progress(quran)?.verseId, v(5, 81));
      controller.restore(before);
      await pumpEventQueue();
      expect(PrefsReadingStore(h.prefs).taraweehLedger()?.nights, isEmpty);
    });

    test('a failed save is kept and tried again', () async {
      final failing = FailingStore(PrefsReadingStore(h.prefs));
      container.dispose();
      h.readingStore = failing;
      container = h.container();
      await listening();
      for (var a = 10; a <= 14; a++) {
        h.engine.emit(heard(at(3, a)));
      }
      expect(await container.read(taraweehLedgerProvider.notifier).flush(), isFalse);
      failing.failing = false;
      expect(await container.read(taraweehLedgerProvider.notifier).flush(), isTrue);
      expect(PrefsReadingStore(h.prefs).taraweehLedger()?.progress(quran)?.verseId, v(3, 14));
    });

    test('the position of earlier versions is carried over, and never overwritten', () async {
      h = await Harness.create(prefs: {
        PrefsReadingStore.taraweehKey: '{"v":1,"verse":${v(5, 81)},"at":"2027-02-08T21:00:00Z"}',
      });
      h.now = DateTime(2027, 2, 9, 21);
      container.dispose();
      container = h.container();
      expect(progress(), v(5, 81));
      expect(container.read(taraweehPositionProvider)?.fixedBy, FixSource.legacy);
      await listening();
      for (var a = 82; a <= 90; a++) {
        h.engine.emit(heard(at(5, a)));
      }
      await container.read(taraweehLedgerProvider.notifier).flush();
      expect(progress(), v(5, 90));
      expect(h.prefs.getString(PrefsReadingStore.taraweehKey), contains('"verse":${v(5, 81)}'));
    });
  });

  group('tonight\'s hint', () {
    TaraweehProgressController controller() => container.read(taraweehLedgerProvider.notifier);

    test('last night: the juz of the ayah after where it stopped', () async {
      await listening();
      for (var a = 70; a <= 81; a++) {
        h.engine.emit(heard(at(5, a)));
      }
      expect(controller().lastNightHint(quran, DateTime(2027, 2, 10, 20, 30)), const JuzHint(7));
    });

    test('nights skipped: no hint (the imam moved on by an unknown amount)', () async {
      await listening();
      for (var a = 70; a <= 81; a++) {
        h.engine.emit(heard(at(5, a)));
      }
      expect(controller().lastNightHint(quran, DateTime(2027, 2, 12, 20, 30)), isNull);
      expect(progress(), v(5, 81), reason: 'the progress itself stays');
    });

    test('back mid-night after the app was killed: tonight so far is the hint', () async {
      await listening();
      for (var a = 1; a <= 30; a++) {
        h.engine.emit(heard(at(6, a)));
      }
      expect(controller().lastNightHint(quran, DateTime(2027, 2, 9, 21, 40)), JuzHint(quran.juzOf(v(6, 31))));
    });
  });

  group('a whole night, simulated through the real tracker', () {
    late QuranMatcher matcher;
    setUpAll(() => matcher = QuranMatcher(indexOf(quran)));

    /// The imam (or anyone) says [text]: chunks of five words, each previewed
    /// then committed, three seconds apart, through [tracker].
    void say(Tracker tracker, String text) {
      final words = text.split(' ');
      for (var i = 0; i < words.length; i += 5) {
        final chunk = words.sublist(i, i + 5 > words.length ? words.length : i + 5).join(' ');
        final half = chunk.split(' ').take(3).join(' ');
        h.engine.emit(heard(fromEngine(tracker.preview(half)), isFinal: false));
        h.now = h.now.add(const Duration(seconds: 3));
        h.engine.emit(heard(fromEngine(tracker.update(chunk))));
      }
    }

    void recite(Tracker tracker, int surah, int from, int to) {
      for (var a = from; a <= to; a++) {
        say(tracker, quran.verse(v(surah, a)).text);
      }
    }

    void rakah(Tracker tracker, int surah, int from, int to) {
      recite(tracker, 1, 1, 7);
      recite(tracker, surah, from, to);
      h.now = h.now.add(const Duration(minutes: 2)); // rukuʿ and sujud
    }

    test('Isha, Taraweeh with Al-Fatiha at every rakʿah, a khatera, qunut and Witr: stopped at 2:176', () async {
      await listening();
      final tracker = Tracker(matcher);
      // Isha, before Taraweeh.
      h.now = DateTime(2027, 2, 9, 20);
      rakah(tracker, 59, 21, 24);
      // A short khatera, quoting the ayah of fasting.
      h.now = DateTime(2027, 2, 9, 20, 30);
      say(tracker, 'أيها الإخوة الكرام إن الله تعالى يقول');
      recite(tracker, 2, 183, 183);
      say(tracker, 'فاغتنموا هذه الليالي المباركة بالطاعة والذكر والدعاء');
      // Taraweeh: four rakʿahs, 2:142–176.
      h.now = DateTime(2027, 2, 9, 21);
      for (final (from, to) in [(142, 150), (151, 158), (159, 167), (168, 176)]) {
        rakah(tracker, 2, from, to);
      }
      // Witr, with qunut quoting 2:201.
      rakah(tracker, 87, 1, 19);
      rakah(tracker, 109, 1, 6);
      rakah(tracker, 112, 1, 4);
      say(tracker, 'اللهم اهدنا فيمن هديت وعافنا فيمن عافيت وتولنا فيمن توليت');
      recite(tracker, 2, 201, 201);

      expect(progress(), v(2, 176));
      // The old single position (the last confident ayah outside Al-Fatiha,
      // predictions included) would have saved the ayah after the qunut's
      // quotation: never recited at all.
      expect(container.read(listenControllerProvider).anchor, pos(2, 202));
    });

    test('the next night continues; Witr directly after does not move it', () async {
      final night1 = TaraweehLedger.empty.correct(v(2, 176), DateTime(2027, 2, 9, 23));
      container.read(taraweehLedgerProvider.notifier).restore(night1);
      h.now = DateTime(2027, 2, 10, 21);
      await listening();
      final tracker = Tracker(matcher);
      for (final (from, to) in [(177, 182), (183, 186)]) {
        rakah(tracker, 2, from, to);
      }
      rakah(tracker, 112, 1, 4);
      rakah(tracker, 113, 1, 5);
      rakah(tracker, 114, 1, 6);
      expect(progress(), v(2, 186));
      expect(container.read(taraweehPositionProvider)!.night, '2027-02-10');
    });
  });
}
