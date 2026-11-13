import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/engine/word_tracker.dart';

import '../support/fakes.dart';

/// The Dart word tracker must reproduce the Python reference
/// (engine/src/rafiq/words.py) call for call: golden file from
/// tools/golden/make_golden.py, simulated CTC letter streams with noise,
/// al-Fatiha, the basmala, pauses and re-anchoring, plus a scenario by hand.
void main() {
  final quran = loadQuran();
  final index = indexOf(quran);
  final basmalaVerses = [
    for (final s in quran.surahs)
      if (s.hasBasmala) s.firstVerseId
  ];

  test('the word tracker follows each scenario exactly as the Python engine does', () {
    final cases =
        (jsonDecode(File('test/golden/word_tracker.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThanOrEqualTo(6));
    var calls = 0;
    for (final c in cases) {
      final tracker = WordTracker(index, basmalaVerses: basmalaVerses);
      final ops = (c['ops'] as List).cast<List<dynamic>>();
      final states = (c['states'] as List).cast<List<dynamic>>();
      for (var i = 0; i < ops.length; i++) {
        final op = ops[i];
        final WordState got;
        switch (op[0]) {
          case 'reset':
            tracker.reset();
            got = tracker.state;
          case 'anchor':
            got = tracker.anchor(op[1] as int);
          case 'pause':
            got = tracker.pause();
          case 'feed':
            got = tracker.feed((op[1] as List).cast<String>());
          default:
            fail('unknown op ${op[0]}');
        }
        final want = states[i];
        final where = '${c['name']}, call $i: $op';
        expect(got.word, want[0], reason: '$where: word');
        expect(got.status.name, want[1], reason: '$where: status');
        expect(got.confidence, closeTo((want[2] as num).toDouble(), 1e-9), reason: '$where: confidence');
        expect(got.basmala, want[3], reason: '$where: basmala');
        calls++;
      }
    }
    expect(calls, greaterThan(3000), reason: 'the scenarios are substantial');
  });

  test('a clean recitation is followed word by word, at a few microseconds a letter', () {
    final tracker = WordTracker(index, basmalaVerses: basmalaVerses);
    final (lo, hi) = index.verseSpan(2050);
    tracker.anchor(lo);
    final watch = Stopwatch()..start();
    var letters = 0;
    for (var p = lo; p < hi; p++) {
      for (final r in index.words[p].runes) {
        tracker.feed([String.fromCharCode(r)]);
        letters++;
      }
      if (p >= lo + 2) {
        expect(tracker.state.status, WordStatus.tracking, reason: 'word ${p - lo}');
        expect(tracker.state.word, p);
      }
    }
    watch.stop();
    // Budget: a CTC model emits ~12 letters a second; even a slow phone has
    // orders of magnitude to spare. Loose bound, so CI machines never flake.
    expect(watch.elapsedMicroseconds / letters, lessThan(2000));
  });
}
