import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/core/engine/matcher.dart';
import 'package:rafiq/core/engine/tracker.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/data/quran.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/data/taraweeh_ledger.dart';

import '../support/fakes.dart';

/// Where Taraweeh stopped, on REAL recognition: the 40 recordings of
/// `eval/results/transcripts` (12 reciters, clean, far and mosque rooms,
/// laptop Whisper; PLAN.md §34), every preview and final, replayed through
/// the real tracker exactly as the phone's listener feeds it (previews
/// `preview`, finals `update`), then through the real listening session and
/// the ledger. The recordings are short passages (four ayahs each, 7:29–32
/// and 26:… ), so whole nights below are stitched from them and say so.
void main() {
  late Quran quran;
  late QuranMatcher matcher;

  final files = Directory('../eval/results/transcripts').existsSync()
      ? (Directory('../eval/results/transcripts')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  setUpAll(() {
    quran = loadQuran();
    matcher = QuranMatcher(indexOf(quran));
  });

  /// One recording: its events and the ayahs it covers (the truth).
  ({String name, List<Map<String, dynamic>> events, List<int> verses}) load(File f) {
    final d = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return (
      name: f.uri.pathSegments.last,
      events: (d['events'] as List).cast<Map<String, dynamic>>(),
      verses: [for (final t in d['timeline'] as List) (t as List)[2] as int],
    );
  }

  /// A listening session fed [recordings] in order, from [start], through a
  /// fresh tracker per session as on the phone; returns the container.
  Future<ProviderContainer> session(
    Harness h,
    List<({String name, List<Map<String, dynamic>> events, List<int> verses})> recordings, {
    required DateTime start,
    bool finals = true,
    bool previews = true,
    ProviderContainer? container,
  }) async {
    final c = container ?? h.container();
    final listen = c.read(listenControllerProvider.notifier);
    await listen.start();
    h.engine.emit(const EngineReady());
    final tracker = Tracker(matcher);
    var offset = Duration.zero;
    for (final r in recordings) {
      for (final e in r.events) {
        final isFinal = e['final'] as bool;
        if ((isFinal && !finals) || (!isFinal && !previews)) continue;
        final text = e['text'] as String;
        final state = isFinal ? tracker.update(text) : tracker.preview(text);
        h.now = start.add(offset + Duration(milliseconds: ((e['end'] as num) * 1000).round()));
        h.engine.emit(Heard(
          text: text,
          start: (e['start'] as num).toDouble(),
          end: (e['end'] as num).toDouble(),
          asrMs: e['asr_ms'] as int,
          state: fromEngine(state),
          isFinal: isFinal,
        ));
      }
      offset += const Duration(minutes: 3);
    }
    await listen.stop();
    return c;
  }

  TaraweehProgress? progressOf(ProviderContainer c) => c.read(taraweehPositionProvider);

  test('the recordings are there', () {
    expect(files, hasLength(40), reason: 'eval/results/transcripts is tracked in git');
  });

  test('each recording alone: its last ayah, or nothing; never anywhere else', () async {
    var last = 0, placed = 0;
    final misses = <String>[];
    for (final f in files) {
      final r = load(f);
      final h = await Harness.create();
      final c = await session(h, [r], start: DateTime(2027, 2, 9, 21));
      final p = progressOf(c);
      if (p != null) {
        placed++;
        expect(r.verses, contains(p.verseId), reason: '${r.name}: ${p.verseId} is outside the passage');
        if (p.verseId == r.verses.last) last++;
      } else {
        misses.add(r.name);
      }
      c.dispose();
    }
    // Measured: printed so a change in either direction is visible.
    // ignore: avoid_print
    print('real recordings: $placed/${files.length} placed, $last at the last ayah; none placed: $misses');
    // Measured 2026-11-13: 39 placed, all 39 at the passage's last ayah; the
    // one left (Sudais, far room) heard too little to say: nothing saved.
    expect(placed, greaterThanOrEqualTo(38));
    expect(last, placed, reason: 'every stopping point saved is the last ayah recited');
  });

  test('previews alone never move the progress (every recording, previews only)', () async {
    for (final f in files) {
      final h = await Harness.create();
      final c = await session(h, [load(f)], start: DateTime(2027, 2, 9, 21), finals: false);
      expect(progressOf(c), isNull, reason: f.path);
      expect(c.read(taraweehLedgerProvider).nights, isEmpty, reason: f.path);
      c.dispose();
    }
  });

  test('stitched night: Taraweeh (7:29–32, real) then other recitation elsewhere (real): the night before decides',
      () async {
    final tar = load(files.firstWhere((f) => f.path.contains('Alafasy_128kbps__mosque__p0')));
    final other = load(files.firstWhere((f) => f.path.contains('Alafasy_128kbps__mosque__p1')));
    expect(tar.verses.first, isNot(other.verses.first));

    // With no night before: two equal passages, neither known to be
    // Taraweeh. Nothing is committed (honest), rather than a guess.
    final h = await Harness.create();
    var c = await session(h, [tar, other], start: DateTime(2027, 2, 9, 21));
    expect(progressOf(c), isNull);
    c.dispose();

    // Last night ended at 7:28 (set by hand): tonight continues it, and the
    // passage after does not count.
    final h2 = await Harness.create();
    c = h2.container();
    c.read(taraweehLedgerProvider.notifier).correct(quran.verseId(7, 28)!, DateTime(2027, 2, 9, 9));
    c = await session(h2, [tar, other], start: DateTime(2027, 2, 9, 21), container: c);
    expect(progressOf(c)?.verseId, tar.verses.last);
    c.dispose();
  });

  test('a session killed mid-night and restarted: the night goes on from what was saved', () async {
    final recordings = [for (final f in files.where((f) => f.path.contains('__p0'))) load(f)];
    final h = await Harness.create();
    // Half the recordings (one passage, many reciters: the same four ayahs
    // over and over, as a long night's repeats), then the process dies.
    final c = await session(h, recordings.take(3).toList(), start: DateTime(2027, 2, 9, 21));
    await c.read(taraweehLedgerProvider.notifier).flush(); // what the pause (or the 3 s timer) saved
    final before = progressOf(c);
    expect(before?.verseId, recordings.first.verses.last);
    c.dispose(); // the process is gone; nothing in memory survives

    final restarted = h.container(); // same storage
    expect(progressOf(restarted), before);
    expect(PrefsReadingStore(h.prefs).taraweehLedger()?.nights.single.runs, isNotEmpty);
    restarted.dispose();
  });
}
