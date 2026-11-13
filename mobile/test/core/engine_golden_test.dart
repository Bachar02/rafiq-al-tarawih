import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/engine/matcher.dart';
import 'package:rafiq/core/engine/quran_index.dart';
import 'package:rafiq/core/engine/segmenter.dart';
import 'package:rafiq/core/engine/tracker.dart';
import 'package:rafiq/core/text/normalize.dart';

import '../support/fakes.dart';

/// The Dart port of the engine must reproduce the Python reference: golden
/// files from tools/golden/make_golden.py (real recorded speech-model output,
/// simulated noisy recitation, and synthetic audio).
Object? golden(String name) => jsonDecode(File('test/golden/$name').readAsStringSync());

QuranIndex? _index;
QuranIndex loadIndex() => _index ??= indexOf(loadQuran());

const _statuses = {'idle': TrackerStatus.idle, 'tracking': TrackerStatus.tracking};

void main() {
  test('the index: the whole Quran as one stream of words', () {
    final index = loadIndex();
    expect(index.verseCount, 6236);
    expect(index.length, greaterThan(77000));
    expect(index.verseSpan(1), (0, 4), reason: 'al-Fatiha 1:1 has four words');
    expect(index.verseAt(0), 1);
    expect(index.verseAt(index.length + 10), 6236);
    expect(index.idf['الله']! < index.idf['الصمد']!, isTrue, reason: 'rare words weigh more');
  });

  test('the matcher returns what the Python engine returns', () {
    final matcher = QuranMatcher(loadIndex());
    final cases = (golden('match.json')! as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThan(150));
    final mismatches = <String>[];
    for (final c in cases) {
      final got = matcher.matchTokens(
        _tokens(c['text'] as String),
        k: 5,
        lo: c['lo'] as int,
        hi: c['hi'] as int?,
      );
      final want = (c['matches'] as List).cast<List<dynamic>>();
      final same = got.length == want.length &&
          [
            for (var i = 0; i < got.length; i++)
              got[i].start == want[i][0] &&
                  got[i].end == want[i][1] &&
                  (got[i].score - (want[i][2] as num)).abs() < 1e-9 &&
                  got[i].firstVerse == want[i][3] &&
                  got[i].lastVerse == want[i][4]
          ].every((ok) => ok);
      if (!same) {
        mismatches.add('${c['text']}\n  python: $want\n  dart:   '
            '${[for (final m in got) '[${m.start}, ${m.end}, ${m.score}, ${m.firstVerse}, ${m.lastVerse}]']}');
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.take(3).join('\n'));
  });

  test("the whole shortlist, its votes and the cap's cut are what the Python engine returns", () {
    final matcher = QuranMatcher(loadIndex());
    final cases = (golden('match.json')! as List).cast<Map<String, dynamic>>();
    var cuts = 0;
    for (final c in cases) {
      final tokens = _tokens(c['text'] as String);
      final (lo, hi) = (c['lo'] as int, c['hi'] as int?);
      final got = matcher.matchAll(tokens, lo: lo, hi: hi);
      final want = (c['all'] as List).cast<List<dynamic>>();
      final where = c['text'];
      expect(got.matches.length, want.length, reason: '$where');
      for (var i = 0; i < want.length; i++) {
        expect([got.matches[i].start, got.matches[i].end], [want[i][0], want[i][1]], reason: '$where #$i');
        expect(got.matches[i].score, closeTo(want[i][2] as num, 1e-9), reason: '$where #$i score');
        expect(got.votes[i], closeTo(want[i][3] as num, 1e-9), reason: '$where #$i votes');
      }
      final cut = c['cut'] as num?;
      expect(got.cut == null, cut == null, reason: '$where cut');
      if (cut != null) {
        cuts++;
        expect(got.cut, closeTo(cut, 1e-9), reason: '$where cut');
      }
      // A top-k search returns the shortlist's first k.
      for (final k in [1, 5, 8]) {
        expect([
          for (final m in matcher.matchTokens(tokens, k: k, lo: lo, hi: hi)) (m.start, m.end, m.score)
        ], [
          for (final m in got.matches.take(k)) (m.start, m.end, m.score)
        ], reason: '$where k=$k');
      }
    }
    expect(cuts, greaterThan(0), reason: 'the cap is exercised');
  });

  test('the tracker follows each scenario exactly as the Python engine does', () {
    final matcher = QuranMatcher(loadIndex());
    final cases = (golden('tracker.json')! as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThan(10));
    var steps = 0, ties = 0;
    for (final c in cases) {
      final tracker = Tracker(matcher);
      final inputs = (c['steps'] as List).cast<Map<String, dynamic>>();
      final states = c['states'] as List;
      for (var i = 0; i < inputs.length; i++) {
        final step = inputs[i];
        TrackerState? got;
        if (step.containsKey('hint')) {
          final range = (step['hint'] as List).cast<int>();
          tracker.hint(range[0], range[1]);
        } else if (step.containsKey('lock')) {
          final range = (step['lock'] as List?)?.cast<int>();
          tracker.lock(range?[0], range?[1]);
        } else if (step.containsKey('position')) {
          got = tracker.setPosition(step['position'] as int);
        } else if (step.containsKey('reset')) {
          tracker.reset();
        } else {
          final text = step['text'] as String;
          got = step['final'] as bool ? tracker.update(text) : tracker.preview(text);
        }
        final want = states[i] as List?;
        if (want == null) continue;
        steps++;
        final where = '${c['name']}, step $i: "${step['text']}"';
        expect(got!.verseId, want[0], reason: '$where: verse');
        expect(got.word, want[1], reason: '$where: word');
        expect(got.status, _statuses[want[2]] ?? TrackerStatus.values.byName(want[2] as String), reason: where);
        // Python rounds confidence to 3 places for its clients.
        expect(got.confidence, closeTo(want[3] as num, 0.0005 + 1e-9), reason: '$where: confidence');
        expect(got.pendingVerse, want[4], reason: '$where: pending');
        expect(got.alternatives, want[5], reason: '$where: alternatives');
        expect(got.upcomingVerse, want[6], reason: '$where: upcoming');
        final candidates = [
          for (final m in got.candidates.take(3)) [m.start, m.end]
        ];
        expect(candidates, [for (final m in want[7] as List) (m as List).sublist(0, 2)], reason: '$where: candidates');
        expect(got.evidence, want[8], reason: '$where: evidence');
        expect(got.tied, want[9], reason: '$where: tied');
        expect(got.tieTrusted, want[10], reason: '$where: tie trusted');
        if ((want[9] as List).isNotEmpty) ties++;
      }
    }
    expect(steps, greaterThan(1500), reason: 'the scenarios are substantial');
    expect(ties, greaterThan(25), reason: 'the tie report is exercised');
  });

  test('the segmenter cuts the same chunks as the Python engine', () {
    final g = golden('segmenter.json')! as Map<String, dynamic>;
    final samples = synthAudio((g['pieces'] as List).cast<List<dynamic>>(), g['noise'] as int);
    final block = g['block'] as int;
    final seg = Segmenter(EnergyVad());
    final got = <List<Object>>[];
    String r(double x) => x.toStringAsFixed(6);
    for (var i = 0; i < samples.length; i += block) {
      final end = i + block < samples.length ? i + block : samples.length;
      for (final s in seg.push(Float32List.sublistView(samples, i, end))) {
        got.add(['final', i + block, r(s.start), r(s.end), s.audio.length]);
      }
      if ((i ~/ block) % 6 == 5) {
        final p = seg.inProgress(0.6);
        if (p != null) got.add(['partial', i + block, r(p.start), r(p.end), p.audio.length]);
      }
    }
    for (final s in seg.flush()) {
      got.add(['flush', samples.length, r(s.start), r(s.end), s.audio.length]);
    }
    final want = [
      for (final e in (g['events'] as List).cast<List<dynamic>>())
        [e[0], e[1], r((e[2] as num).toDouble()), r((e[3] as num).toDouble()), e[4]]
    ];
    expect(got, want);
  });
}

List<String> _tokens(String text) => tokenize(text);

/// The same integer recipe as tools/golden/make_golden.py's synth_audio.
Float32List synthAudio(List<List<dynamic>> pieces, int noise) {
  final out = <double>[];
  var x = 1448;
  for (final piece in pieces) {
    final seconds = (piece[0] as num).toDouble(), amp = piece[1] as int, period = piece[2] as int;
    for (var t = 0; t < (seconds * 16000).toInt(); t++) {
      x = (1103515245 * x + 12345) % 2147483648;
      final n = (x >> 16) % (2 * noise + 1) - noise;
      final p = t % period;
      final tone = 2 * p < period ? (4 * p * amp) ~/ period - amp : 3 * amp - (4 * p * amp) ~/ period;
      out.add((tone + n).clamp(-32768, 32767) / 32768.0);
    }
  }
  return Float32List.fromList(out);
}
