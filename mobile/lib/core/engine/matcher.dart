/// Text -> ranked candidate positions in the Quran. A port of
/// `engine/src/rafiq/matching/{align,matcher}.py`, kept exact: the golden
/// tests (tools/golden/make_golden.py) replay the Python engine's results.
///
/// Two stages:
/// 1. **Retrieval** (cheap, recall-oriented). Every query word votes for the
///    stream offset at which the query would start for that word to line up.
///    Votes are IDF-weighted, so rare words dominate. Out-of-vocabulary words
///    (misheard spellings) vote through their nearest vocabulary words.
/// 2. **Rescoring** (precise). The best offsets are re-scored by word-level
///    local alignment against the stream, which also yields the exact span.
library;

import 'dart:math' as math;

import 'quran_index.dart';

class AlignConfig {
  const AlignConfig({this.gap = 0.5, this.minWordSim = 0.5});

  /// Cost of skipping a word on either side.
  final double gap;

  /// Below this similarity two words count as a full mismatch.
  final double minWordSim;
}

class Alignment {
  const Alignment(this.score, this.start, this.end, this.queryStart, this.queryEnd);

  static const none = Alignment(0, 0, 0, 0, 0);

  /// An exact match of n words scores n.
  final double score;

  /// Window indices of the aligned span, `[start, end)`.
  final int start;
  final int end;
  final int queryStart;
  final int queryEnd;
}

/// Levenshtein distance over UTF-16 code units (the normalized text is
/// basic Arabic letters, one unit each).
int levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= b.length; j++) {
      final sub = prev[j - 1] + (ca == b.codeUnitAt(j - 1) ? 0 : 1);
      final del = prev[j] + 1, ins = cur[j - 1] + 1;
      cur[j] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}

/// Length of the longest common subsequence.
int lcsLength(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var prev = List<int>.filled(b.length + 1, 0);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    final ca = a.codeUnitAt(i);
    cur[0] = 0;
    for (var j = 0; j < b.length; j++) {
      cur[j + 1] = ca == b.codeUnitAt(j) ? prev[j] + 1 : math.max(prev[j + 1], cur[j]);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}

/// rapidfuzz's `Levenshtein.normalized_similarity`.
double levenshteinSimilarity(String a, String b) {
  final m = math.max(a.length, b.length);
  if (m == 0) return 1.0;
  return 1.0 - levenshtein(a, b) / m;
}

/// rapidfuzz's `fuzz.ratio`: the InDel similarity, 0..100.
double fuzzRatio(String a, String b) {
  final total = a.length + b.length;
  if (total == 0) return 100.0;
  final dist = total - 2 * lcsLength(a, b);
  return (1.0 - dist / total) * 100;
}

/// Substitution score in [-1, 1]: +1 identical, -1 unrelated.
double wordSimilarity(String a, String b, AlignConfig cfg) {
  if (a == b) return 1.0;
  final sim = levenshteinSimilarity(a, b);
  if (sim < cfg.minWordSim) return -1.0;
  return 2.0 * sim - 1.0;
}

/// Best local alignment (Smith-Waterman, word level) of [query] inside [window].
Alignment align(List<String> query, List<String> window, [AlignConfig cfg = const AlignConfig()]) {
  final n = query.length, m = window.length;
  if (n == 0 || m == 0) return Alignment.none;
  final sims = <String, double>{};
  final gap = cfg.gap;
  // Rolling rows; each cell carries (score, window start, query start) so the
  // span is known without a traceback matrix.
  var prevScore = List<double>.filled(m + 1, 0), curScore = List<double>.filled(m + 1, 0);
  var prevWs = List<int>.generate(m + 1, (j) => j), curWs = List<int>.filled(m + 1, 0);
  var prevQs = List<int>.filled(m + 1, 0), curQs = List<int>.filled(m + 1, 0);
  var best = Alignment.none;
  for (var i = 1; i <= n; i++) {
    final qw = query[i - 1];
    curScore[0] = 0;
    curWs[0] = 0;
    curQs[0] = i;
    for (var j = 1; j <= m; j++) {
      final ww = window[j - 1];
      final s = sims.putIfAbsent('$qw\u0000$ww', () => wordSimilarity(qw, ww, cfg));
      var score = prevScore[j - 1] + s, ws = prevWs[j - 1], qs = prevQs[j - 1];
      if (prevScore[j] - gap > score) {
        score = prevScore[j] - gap;
        ws = prevWs[j];
        qs = prevQs[j];
      }
      if (curScore[j - 1] - gap > score) {
        score = curScore[j - 1] - gap;
        ws = curWs[j - 1];
        qs = curQs[j - 1];
      }
      if (score <= 0.0) {
        score = 0.0;
        ws = j;
        qs = i;
      } else if (score > best.score) {
        best = Alignment(score, ws, j, qs, i);
      }
      curScore[j] = score;
      curWs[j] = ws;
      curQs[j] = qs;
    }
    (prevScore, curScore) = (curScore, prevScore);
    (prevWs, curWs) = (curWs, prevWs);
    (prevQs, curQs) = (curQs, prevQs);
  }
  return best;
}

class MatchConfig {
  const MatchConfig({
    this.retrieve = 40,
    this.fuzzyLimit = 3,
    this.fuzzyCutoff = 70.0,
    this.fuzzyWeight = 0.7,
    this.voteSpread = 2,
    this.minScore = 0.25,
    this.align = const AlignConfig(),
  });

  /// Offsets kept from voting for rescoring.
  final int retrieve;

  /// Vocabulary neighbours tried for an unknown word.
  final int fuzzyLimit;

  /// Ratio needed for a neighbour to vote.
  final double fuzzyCutoff;

  /// Neighbour votes count this much of an exact vote.
  final double fuzzyWeight;

  /// Offsets within this many words pool their votes.
  final int voteSpread;

  /// Matches scoring below this are discarded.
  final double minScore;
  final AlignConfig align;
}

/// A span of the stream that the query aligned to.
class QuranMatch {
  const QuranMatch({
    required this.start,
    required this.end,
    required this.score,
    required this.firstVerse,
    required this.lastVerse,
  });

  /// Stream word indices, `[start, end)`.
  final int start;
  final int end;

  /// Alignment score per query word, 0..1.
  final double score;
  final int firstVerse;
  final int lastVerse;

  /// Where the reciter is now: the verse of the last matched word.
  int get verseId => lastVerse;
}

/// [items] sorted by [key], highest first, equal keys in their original
/// order (Python's `sorted(..., reverse=True)` is stable).
List<T> sortedDesc<T>(Iterable<T> items, double Function(T) key) {
  final list = items.toList();
  final keys = [for (final x in list) key(x)];
  final order = List<int>.generate(list.length, (i) => i)
    ..sort((a, b) {
      final c = keys[b].compareTo(keys[a]);
      return c != 0 ? c : a - b;
    });
  return [for (final i in order) list[i]];
}

class QuranMatcher {
  QuranMatcher(this.index, [this.config = const MatchConfig()]);

  final QuranIndex index;
  final MatchConfig config;
  final _neighbourCache = <String, List<(String, double)>>{};

  /// Top [k] non-overlapping matches for [tokens], best first, searching the
  /// stream range `[lo, hi)`.
  List<QuranMatch> matchTokens(List<String> tokens, {int k = 5, int lo = 0, int? hi}) {
    if (tokens.isEmpty) return const [];
    final offsets = _retrieve(tokens, lo, hi ?? index.length);
    final matches = [for (final off in offsets) scoreWindow(tokens, off, off + tokens.length)];
    return _select(matches, k);
  }

  /// Align [tokens] against the stream around `[start, end)`, padded so a few
  /// inserted or deleted words cannot push the true span out of reach.
  QuranMatch scoreWindow(List<String> tokens, int start, int end) {
    final n = tokens.length;
    final pad = math.max(3, n ~/ 2);
    final wLo = math.max(0, start - pad);
    final wHi = math.min(index.length, end + pad);
    final a = align(tokens, index.words.sublist(wLo, math.max(wLo, wHi)), config.align);
    final s = wLo + a.start;
    final e = math.min<int>(wLo + math.max<int>(a.end, a.start + 1), index.length);
    return QuranMatch(
      start: s,
      end: e,
      score: math.max(0.0, a.score / n),
      firstVerse: index.verseAt(s),
      lastVerse: index.verseAt(e - 1),
    );
  }

  /// Vocabulary words close to an out-of-vocabulary [word], with weights:
  /// rapidfuzz's `process.extract` (best score first, then vocabulary order).
  List<(String, double)> _neighbours(String word) => _neighbourCache.putIfAbsent(word, () {
        final cfg = config;
        final scored = <(int, double)>[];
        for (var i = 0; i < index.vocab.length; i++) {
          final s = fuzzRatio(word, index.vocab[i]);
          if (s >= cfg.fuzzyCutoff) scored.add((i, s));
        }
        scored.sort((a, b) {
          final c = b.$2.compareTo(a.$2);
          return c != 0 ? c : a.$1 - b.$1;
        });
        return [for (final (i, s) in scored.take(cfg.fuzzyLimit)) (index.vocab[i], cfg.fuzzyWeight * s / 100.0)];
      });

  List<int> _retrieve(List<String> tokens, int lo, int hi) {
    final votes = <int, double>{};
    for (var qi = 0; qi < tokens.length; qi++) {
      final token = tokens[qi];
      final variants = index.postings.containsKey(token) ? [(token, 1.0)] : _neighbours(token);
      for (final (word, weight) in variants) {
        final w = weight * index.idf[word]!;
        for (final pos in index.postings[word]!) {
          if (lo <= pos && pos < hi) votes[pos - qi] = (votes[pos - qi] ?? 0.0) + w;
        }
      }
    }
    if (votes.isEmpty) return const [];
    // Pool nearby offsets: an inserted or dropped word shifts the diagonal.
    final spread = config.voteSpread;
    final pooled = <int, double>{};
    for (final off in votes.keys) {
      var sum = 0.0;
      for (var d = -spread; d <= spread; d++) {
        sum += votes[off + d] ?? 0.0;
      }
      pooled[off] = sum;
    }
    final chosen = <int>[];
    for (final off in sortedDesc(pooled.keys, (o) => pooled[o]!)) {
      if (chosen.every((c) => (off - c).abs() > spread)) {
        chosen.add(off);
        if (chosen.length >= config.retrieve) break;
      }
    }
    return chosen;
  }

  /// Best first, dropping matches that overlap a better one.
  List<QuranMatch> _select(List<QuranMatch> matches, int k) {
    final out = <QuranMatch>[];
    for (final m in sortedDesc(matches, (m) => m.score)) {
      if (m.score < config.minScore) break;
      if (out.any((o) => m.start < o.end && o.start < m.end)) continue;
      out.add(m);
      if (out.length >= k) break;
    }
    return out;
  }
}
