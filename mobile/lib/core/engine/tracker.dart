/// Stateful position tracking: "given everything heard so far, where is the
/// imam?". A port of `engine/src/rafiq/tracking.py`, kept exact (golden tests).
///
/// The matcher answers "where could this chunk be?", often ambiguously (the
/// refrain of Ar-Rahman occurs 31 times). The tracker resolves that with
/// context, using a small beam search over hypotheses:
///
///     score(new) = max over previous h of decay * score(h) + transition(h -> c)
///                  + emission(c)
///
/// * **emission** is the matcher's alignment score for the chunk.
/// * **transition** encodes how imams move: onward is free, a short step back
///   (repeating an ayah) is cheap, anything far is expensive.
/// * **excursions** are regions the reciter visits and returns from:
///   al-Fatiha at the start of every rakʿah.
///
/// On top sits a display policy: a far jump must win [TrackerConfig.confirm]
/// times in a row before the screen moves.
library;

import 'dart:math' as math;

import '../text/normalize.dart';
import 'matcher.dart';
import 'quran_index.dart';

enum TrackerStatus { idle, tracking, uncertain, lost }

class TrackerConfig {
  const TrackerConfig({
    this.beam = 8,
    this.candidates = 8,
    this.localHyps = 3,
    this.localAhead = 40,
    this.minEmission = 0.45,
    this.decay = 0.6,
    this.missCost = 0.5,
    this.confirm = 2,
    this.coldStartConfidence = 0.3,
    this.alternativeMargin = 0.5,
    this.emissionWeight = 0.5,
    this.fullEvidenceWords = 3,
    this.unknownExitCost = 0.3,
    this.hintBonus = 0.3,
    this.userPositionScore = 2.5,
    this.lostAfter = 4,
    this.excursions = const [(1, 7)],
  });

  /// Hypotheses kept between steps.
  final int beam;

  /// Global matches requested per chunk.
  final int candidates;

  /// Top hypotheses that also get a local "expected next" check.
  final int localHyps;

  /// Words beyond a hypothesis searched by that check.
  final int localAhead;

  /// A chunk whose best match scores lower is treated as noise.
  final double minEmission;

  /// Weight of history against the newest chunk.
  final double decay;

  /// Penalty for a hypothesis this chunk did not support.
  final double missCost;

  /// Consecutive wins a far jump needs before it is shown.
  final int confirm;

  /// Confidence needed to show the very first position.
  final double coldStartConfidence;

  /// Rivals within this of the best are reported as alternatives.
  final double alternativeMargin;

  /// How much the newest chunk's own match quality scales confidence.
  final double emissionWeight;

  /// Chunks shorter than this count as proportionally weaker evidence.
  final int fullEvidenceWords;

  /// Leaving al-Fatiha when the place before it was never seen.
  final double unknownExitCost;

  /// Emission bonus inside the user's hint while searching.
  final double hintBonus;

  /// Weight of "the imam is here" from the user.
  final double userPositionScore;

  /// Consecutive noise chunks before "lost".
  final int lostAfter;

  /// Verse-id ranges the reciter visits and returns from (al-Fatiha).
  final List<(int, int)> excursions;
}

/// Log-score (<= 0) of moving from stream position `prevEnd` to `nextStart`.
class DefaultTransition {
  const DefaultTransition({
    this.slack = 3,
    this.forwardCost = 0.01,
    this.near = 40,
    this.back = 80,
    this.repeatCost = 0.4,
    this.farCost = 1.2,
  });

  final int slack;
  final double forwardCost;
  final int near;
  final int back;
  final double repeatCost;
  final double farCost;

  double call(int prevEnd, int nextStart) {
    final jump = nextStart - prevEnd;
    if (-slack <= jump && jump <= slack) return 0.0;
    if (slack < jump && jump <= near) return -forwardCost * (jump - slack);
    if (-back <= jump && jump < -slack) return -repeatCost;
    return -farCost;
  }
}

class Hypothesis {
  const Hypothesis({required this.end, required this.score, required this.emission, this.anchor});

  /// Stream position just after the last matched word.
  final int end;
  final double score;
  final double emission;

  /// Where to return to after an excursion.
  final int? anchor;
}

/// What the tracker says the screen should show.
class TrackerState {
  const TrackerState({
    required this.verseId,
    required this.word,
    required this.status,
    required this.confidence,
    this.candidates = const [],
    this.pendingVerse,
    this.alternatives = const [],
    this.upcomingVerse,
  });

  static const idle = TrackerState(verseId: null, word: null, status: TrackerStatus.idle, confidence: 0);

  /// The displayed verse, and stream position (the last recited word).
  final int? verseId;
  final int? word;
  final TrackerStatus status;

  /// 0..1 (unrounded; the Python engine rounds to 3 places for its clients).
  final double confidence;

  /// This chunk's matches.
  final List<QuranMatch> candidates;

  /// A far jump (or a first guess) awaiting confirmation.
  final int? pendingVerse;

  /// Other plausible verses, when ambiguous.
  final List<int> alternatives;

  /// The displayed ayah was recited to its end: where the imam goes next.
  final int? upcomingVerse;

  int? get showing => upcomingVerse ?? verseId;

  TrackerState withStatus(TrackerStatus status, List<QuranMatch> candidates) => TrackerState(
        verseId: verseId,
        word: word,
        status: status,
        confidence: 0.0,
        candidates: candidates,
        pendingVerse: pendingVerse,
        alternatives: alternatives,
        upcomingVerse: upcomingVerse,
      );
}

class Tracker {
  Tracker(this.matcher, {this.config = const TrackerConfig(), this.transition = const DefaultTransition()})
      : index = matcher.index {
    _excursionSpans = [for (final (a, b) in config.excursions) (index.verseSpan(a).$1, index.verseSpan(b).$2)];
    reset();
  }

  final QuranMatcher matcher;
  final QuranIndex index;
  final TrackerConfig config;
  final DefaultTransition transition;
  late final List<(int, int)> _excursionSpans;

  /// Stream ranges `[lo, hi)`; both survive [reset] (they describe the session).
  (int, int)? _hint;
  (int, int)? _lock;

  List<Hypothesis> _hyps = const [];
  int? _shown; // displayed stream position (end, exclusive)
  int? _shownAnchor; // displayed position before entering an excursion
  int? _pending;
  int _pendingCount = 0;
  int _misses = 0;
  TrackerState _state = TrackerState.idle;

  TrackerState get state => _state;

  void reset() {
    _hyps = const [];
    _shown = null;
    _shownAnchor = null;
    _pending = null;
    _pendingCount = 0;
    _misses = 0;
    _state = TrackerState.idle;
  }

  /// Optional "the imam is in this surah / juz": helps only while searching.
  void hint(int? firstVerse, [int? lastVerse]) {
    if (firstVerse == null) {
      _hint = null;
      return;
    }
    _hint = (index.verseSpan(firstVerse).$1, index.verseSpan(lastVerse ?? firstVerse).$2);
  }

  /// "Never look outside these verses" (al-Fatiha excepted); null unlocks.
  void lock(int? firstVerse, [int? lastVerse]) {
    if (firstVerse == null) {
      _lock = null;
      return;
    }
    _lock = (index.verseSpan(firstVerse).$1, index.verseSpan(lastVerse ?? firstVerse).$2);
  }

  /// "The imam is here": continue from the start of [verseId].
  TrackerState setPosition(int verseId) {
    final start = index.verseSpan(verseId).$1;
    _hyps = [Hypothesis(end: start, score: config.userPositionScore, emission: 1.0)];
    _shown = start + 1;
    _shownAnchor = null;
    _pending = null;
    _pendingCount = 0;
    _misses = 0;
    _state = TrackerState(verseId: verseId, word: start, status: TrackerStatus.tracking, confidence: 1.0);
    return _state;
  }

  bool _allowed(int pos) {
    final lock = _lock;
    if (lock == null) return true;
    return (lock.$1 <= pos && pos < lock.$2) || _inExcursion(pos);
  }

  /// True until the first position is shown, and again once lost.
  bool get searching => _shown == null || _misses >= config.lostAfter;

  /// What [update] would show, without committing it (live partials).
  TrackerState preview(String text) {
    final (hyps, shown, anchor, pending, count, misses, state) =
        (_hyps, _shown, _shownAnchor, _pending, _pendingCount, _misses, _state);
    try {
      return update(text);
    } finally {
      _hyps = hyps;
      _shown = shown;
      _shownAnchor = anchor;
      _pending = pending;
      _pendingCount = count;
      _misses = misses;
      _state = state;
    }
  }

  /// Feed one transcribed chunk; returns what the screen should show now.
  TrackerState update(String text) {
    final cfg = config;
    final tokens = tokenize(text);
    final hint = searching ? _hint : null;
    final candidates = _candidates(tokens, hint);
    // A one-word chunk matches in hundreds of places: weak evidence.
    final evidence = math.min(1.0, tokens.length / cfg.fullEvidenceWords);
    final bestEmission = evidence * candidates.fold<double>(0.0, (m, c) => math.max(m, c.score));

    if (tokens.isEmpty || bestEmission < cfg.minEmission) {
      _misses += 1;
      final status = _shown == null
          ? TrackerStatus.idle
          : _misses >= cfg.lostAfter
              ? TrackerStatus.lost
              : TrackerStatus.uncertain;
      _state = _state.withStatus(status, candidates);
      return _state;
    }
    _misses = 0;
    _hyps = _advance(candidates, evidence, hint);
    _state = _display(candidates);
    return _state;
  }

  // -- search ---------------------------------------------------------------

  List<QuranMatch> _candidates(List<String> tokens, (int, int)? hint) {
    if (tokens.isEmpty) return const [];
    final cfg = config;
    final found = <QuranMatch>[];
    final lock = _lock;
    if (lock == null) {
      found.addAll(matcher.matchTokens(tokens, k: cfg.candidates));
    } else {
      found.addAll(matcher.matchTokens(tokens, k: cfg.candidates, lo: lock.$1, hi: lock.$2));
      for (final (lo, hi) in _excursionSpans) {
        found.addAll(matcher.matchTokens(tokens, k: cfg.candidates, lo: lo, hi: hi));
      }
    }
    if (hint != null) found.addAll(matcher.matchTokens(tokens, k: cfg.candidates, lo: hint.$1, hi: hint.$2));
    // Always check "right where I expect".
    for (final h in _hyps.take(cfg.localHyps)) {
      final origins = <int>{h.end, if (h.anchor != null) h.anchor!};
      for (final origin in origins) {
        final local = matcher.scoreWindow(tokens, origin, origin + cfg.localAhead);
        if (local.score > 0) found.add(local);
      }
    }
    final unique = <(int, int), QuranMatch>{};
    for (final m in found) {
      if (!_allowed(m.start)) continue;
      final key = (m.start, m.end);
      final had = unique[key];
      if (had == null || m.score > had.score) unique[key] = m;
    }
    return sortedDesc(unique.values, (m) => m.score);
  }

  bool _inExcursion(int pos) => _excursionSpans.any((s) => s.$1 <= pos && pos < s.$2);

  /// Score of h -> c, and the anchor the new hypothesis inherits.
  (double, int?) _transition(Hypothesis h, QuranMatch c) {
    if (_inExcursion(c.start)) {
      final inside = _inExcursion(h.end - 1);
      final anchor = inside ? h.anchor : h.end;
      final t = inside ? transition.call(h.end, c.start) : -0.1;
      return (math.max(t, -0.1), anchor);
    }
    if (_inExcursion(h.end - 1) && h.anchor == null) return (-config.unknownExitCost, null);
    return (transition.call(h.anchor ?? h.end, c.start), null);
  }

  List<Hypothesis> _advance(List<QuranMatch> candidates, double evidence, (int, int)? hint) {
    final cfg = config;
    final prior = _hyps;
    final next = <Hypothesis>[];
    for (final c in candidates) {
      var emission = evidence * c.score;
      if (emission < cfg.minEmission * 0.5) continue;
      if (hint != null && hint.$1 <= c.start && c.start < hint.$2) emission += cfg.hintBonus;
      var bestPrev = 0.0;
      int? anchor;
      if (prior.isNotEmpty) {
        bestPrev = double.negativeInfinity;
        for (final h in prior) {
          final (t, a) = _transition(h, c);
          final s = cfg.decay * h.score + t;
          if (s > bestPrev) {
            bestPrev = s;
            anchor = a;
          }
        }
      }
      next.add(Hypothesis(end: c.end, score: bestPrev + emission, emission: emission, anchor: anchor));
    }
    // Every hypothesis may survive a chunk that does not support it.
    for (final h in prior) {
      next.add(Hypothesis(end: h.end, score: cfg.decay * h.score - cfg.missCost, emission: 0.0, anchor: h.anchor));
    }
    final kept = <Hypothesis>[];
    for (final h in sortedDesc(next, (h) => h.score)) {
      if (kept.every((k) => (h.end - k.end).abs() > 2)) {
        kept.add(h);
        if (kept.length >= cfg.beam) break;
      }
    }
    return kept;
  }

  // -- display policy -------------------------------------------------------

  /// The next ayah, if [word] is (within a word of) the end of its ayah.
  int? _upcoming(int word) {
    final verse = index.verseAt(word);
    final (start, end) = index.verseSpan(verse);
    final slack = end - start >= 4 ? 1 : 0;
    if (end - 1 - word > slack) return null;
    if (_inExcursion(word)) return _shownAnchor != null ? index.verseAt(_shownAnchor!) : null;
    return verse < index.verseCount ? verse + 1 : null;
  }

  bool _isNear(int a, int b) => transition.call(a, b) > -transition.farCost;

  TrackerState _display(List<QuranMatch> candidates) {
    final cfg = config;
    final best = _hyps.first;
    final rivals = [
      for (final h in _hyps.skip(1))
        if (!_isNear(best.end, h.end) && !_isNear(h.end, best.end)) h
    ];
    final margin = rivals.isNotEmpty ? best.score - rivals.first.score : best.score;
    final quality = 1.0 - cfg.emissionWeight * (1.0 - math.min(best.emission, 1.0));
    final confidence = quality * (1.0 - math.exp(-2.0 * math.max(margin, 0.0)));

    bool accept;
    if (_shown == null) {
      accept = confidence >= cfg.coldStartConfidence;
    } else {
      accept = _isNear(_shown!, best.end) ||
          _inExcursion(best.end - 1) ||
          (_shownAnchor != null && _isNear(_shownAnchor!, best.end));
    }
    if (!accept) {
      if (_pending != null && _isNear(_pending!, best.end)) {
        _pendingCount += 1;
      } else {
        _pendingCount = 1;
      }
      _pending = best.end;
      accept = _pendingCount >= cfg.confirm;
      if (_shown == null) accept = accept && confidence >= cfg.coldStartConfidence / 3;
    }

    if (accept) {
      if (_inExcursion(best.end - 1)) {
        if (!_inExcursion(_shown != null ? _shown! - 1 : -1)) _shownAnchor = _shown;
      } else {
        _shownAnchor = null;
      }
      _shown = best.end;
      _pending = null;
      _pendingCount = 0;
    }

    final pendingVerse = _pending != null ? index.verseAt(_pending! - 1) : null;
    final alternatives = <int>[];
    for (final h in rivals) {
      final v = index.verseAt(h.end - 1);
      if (best.score - h.score > cfg.alternativeMargin || alternatives.length == 3) break;
      if (!alternatives.contains(v)) alternatives.add(v);
    }
    if (_shown == null) {
      return TrackerState(
        verseId: null,
        word: null,
        status: TrackerStatus.uncertain,
        confidence: confidence,
        candidates: candidates,
        pendingVerse: pendingVerse,
        alternatives: alternatives,
      );
    }
    final word = _shown! - 1;
    final status = confidence >= 0.5 && _pending == null ? TrackerStatus.tracking : TrackerStatus.uncertain;
    return TrackerState(
      verseId: index.verseAt(word),
      word: word,
      status: status,
      confidence: confidence,
      candidates: candidates,
      pendingVerse: pendingVerse,
      alternatives: alternatives,
      upcomingVerse: status == TrackerStatus.tracking ? _upcoming(word) : null,
    );
  }
}
