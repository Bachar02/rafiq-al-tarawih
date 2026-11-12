/// Word-level tracking: which word of the ayah is the imam reciting now?
/// A port of `engine/src/rafiq/words.py`, kept exact (golden tests).
///
/// The ayah tracker answers "where in the Quran?" from Whisper text. This
/// answers "which word?" from the letters a streaming CTC model emits, one
/// every 80 ms or so. It is anchored by the ayah tracker and follows the
/// known text from there: alignment, not recognition. Each heard letter
/// extends an edit-distance alignment against a window of the expected text
/// (about 20 words behind the imam and 30 ahead):
///
///     D'[j] = min(D[j-1] + sub(u, ref[j-1]),   // u says ref letter j-1
///                 D[j]   + ins(u),             // u is extra
///                 D'[j-1] + del(ref[j-1]))     // ref letter j-1 not heard
///
/// On top: cheap silent letters and similar sounds (tajweed, orthography), a
/// fixed cost to go back to any earlier word start (the imam repeats), the
/// basmala as an optional segment, a cap so any position in the window can
/// be found again, and al-Fatiha as its own window. When the imam leaves the
/// window, the recent error rate climbs and the word is no longer shown; the
/// caller re-anchors from the ayah tracker.
///
/// It never uses time and builds confidence from sums and ratios only, so it
/// is independent of the speech model and reproduces Python exactly.
library;

import '../text/normalize.dart';
import 'quran_index.dart';

enum WordStatus { idle, tracking, uncertain, lost }

/// Written but often not heard: long vowels and the alef of hamzat al-wasl or tanween.
const _weak = {'ا', 'و', 'ي'};

/// Sun letters: the lam of al- before them is assimilated ("ash-shams").
const _sun = {'ت', 'ث', 'د', 'ذ', 'ر', 'ز', 'س', 'ش', 'ص', 'ض', 'ط', 'ظ', 'ل', 'ن'};

/// Letters a speech model confuses (emphatic and plain, similar sounds).
const _similarPairs = ['ضد', 'ظذ', 'ذز', 'صس', 'طت', 'حه', 'قك', 'عا', 'ثس', 'غخ'];
final _similar = {
  for (final p in _similarPairs) ...[p, '${p[1]}${p[0]}'],
};

class WordTrackerConfig {
  const WordTrackerConfig({
    this.behind = 20,
    this.ahead = 30,
    this.anchorSlack = 12,
    this.subCost = 1.0,
    this.similarCost = 0.5,
    this.insCost = 1.0,
    this.weakInsCost = 0.5,
    this.delCost = 1.0,
    this.weakDelCost = 0.4,
    this.backCost = 2.0,
    this.resyncCost = 6.0,
    this.errorWindow = 12,
    this.maxError = 0.45,
    this.burst = 3,
    this.burstCost = 2.0,
    this.minMargin = 1.0,
    this.minLetters = 8,
    this.confirm = 4,
    this.lostAfter = 30,
    this.excursions = const [(1, 7)],
  });

  /// Words of the window behind the imam: how far back a repetition is found.
  final int behind;

  /// Words of the window ahead of the imam.
  final int ahead;

  /// Words after an anchor where the imam may already be (the anchor is late).
  final int anchorSlack;

  final double subCost;

  /// A letter heard as a similar-sounding one.
  final double similarCost;

  /// A heard letter that is not in the text.
  final double insCost;
  final double weakInsCost;

  /// A letter of the text that was not heard.
  final double delCost;
  final double weakDelCost;

  /// Going back to an earlier word start (the imam repeats).
  final double backCost;

  /// No position is ever worse than the best by more than this.
  final double resyncCost;

  /// Letters over which the recent error rate is measured.
  final int errorWindow;

  /// Recent cost per letter above this: not sure where the imam is.
  final double maxError;

  /// ...and so is [burstCost] over the last [burst] letters: he has just left
  /// the text (a repeat, al-Fatiha), so stop highlighting at once.
  final int burst;
  final double burstCost;

  /// The best must beat every position more than 2 words away by this.
  final double minMargin;

  /// Letters after an anchor before a word is first shown.
  final int minLetters;

  /// Letters a backward or far move must hold before it is shown.
  final int confirm;

  /// Consecutive unsure letters before the word is no longer shown.
  final int lostAfter;

  /// Verse ranges the imam leaves for where he was, not for what follows:
  /// al-Fatiha. Anchored inside one, the window ends with it.
  final List<(int, int)> excursions;
}

class WordState {
  const WordState(this.word, this.status, this.confidence, [this.basmala]);

  /// Stream position of the word being recited (null: not shown).
  final int? word;
  final WordStatus status;

  /// 0..1: low recent error and a clear margin over rivals.
  final double confidence;

  /// Reciting the basmala before this verse id ([word] is then null).
  final int? basmala;

  @override
  String toString() => 'WordState($word, ${status.name}, $confidence, $basmala)';
}

class WordTracker {
  /// [basmalaVerses]: verse ids preceded by a recited basmala (ayah 1 of every
  /// surah but al-Fatiha and at-Tawbah), from the Quran data.
  WordTracker(this.index, {required Iterable<int> basmalaVerses, this.config = const WordTrackerConfig()})
      : _basmalaAt = {for (final v in basmalaVerses.toList()..sort()) index.verseSpan(v).$1: v},
        _basmalaWords = index.words.sublist(index.verseSpan(1).$1, index.verseSpan(1).$2),
        _excursions = [
          for (final (a, b) in config.excursions) (index.verseSpan(a).$1, index.verseSpan(b).$2),
        ] {
    reset();
  }

  WordTracker._copyOf(WordTracker o)
      : index = o.index,
        config = o.config,
        _basmalaAt = o._basmalaAt,
        _basmalaWords = o._basmalaWords,
        _excursions = o._excursions {
    _anchored = o._anchored;
    _letters = List.of(o._letters);
    _weakAt = List.of(o._weakAt);
    _pos = List.of(o._pos);
    _bas = List.of(o._bas);
    _keys = List.of(o._keys);
    _starts = List.of(o._starts);
    _skips = Map.of(o._skips);
    _d = List.of(o._d);
    _w0 = o._w0;
    _w1 = o._w1;
    _end = o._end;
    _total = o._total;
    _ring = List.of(o._ring);
    _lettersSeen = o._lettersSeen;
    _shown = o._shown;
    _pending = o._pending;
    _pendingCount = o._pendingCount;
    _okRun = o._okRun;
    _unsure = o._unsure;
    _resume = o._resume;
    _prevBest = o._prevBest;
    _state = o._state;
  }

  /// An independent copy (sharing the index): a snapshot to preview a live
  /// partial transcript on, so the breath can be fed again from where it began.
  WordTracker copy() => WordTracker._copyOf(this);

  final QuranIndex index;
  final WordTrackerConfig config;
  final Map<int, int> _basmalaAt;
  final List<String> _basmalaWords;
  final List<(int, int)> _excursions;

  bool _anchored = false;
  List<String> _letters = [];
  List<bool> _weakAt = [];
  List<int> _pos = [];
  List<int> _bas = [];
  List<int> _keys = [];
  List<int> _starts = [];
  Map<int, int> _skips = {};
  List<double> _d = [0.0];
  int _w0 = 0, _w1 = 0, _end = 0;
  double _total = 0.0;
  List<double> _ring = [];
  int _lettersSeen = 0;
  int? _shown, _pending;
  int _pendingCount = 0, _okRun = 0, _unsure = 0, _resume = 0, _prevBest = 0;
  WordState _state = const WordState(null, WordStatus.idle, 0.0);

  WordState get state => _state;

  /// Forget everything: idle until the next [anchor].
  void reset() {
    _anchored = false;
    _letters = [];
    _weakAt = [];
    _pos = [];
    _bas = [];
    _keys = [];
    _starts = [];
    _skips = {};
    _d = [0.0];
    _w0 = _w1 = 0;
    _end = index.length;
    _total = 0.0;
    _ring = [];
    _lettersSeen = 0;
    _shown = null;
    _pending = null;
    _pendingCount = 0;
    _okRun = 0;
    _unsure = 0;
    _resume = 0;
    _prevBest = 0;
    _state = const WordState(null, WordStatus.idle, 0.0);
  }

  /// The ayah tracker says the imam is at (or a little past) stream position [word].
  WordState anchor(int word) {
    final cfg = config;
    word = word.clamp(0, index.length - 1);
    reset();
    _anchored = true;
    for (final (lo, hi) in _excursions) {
      if (lo <= word && word < hi) _end = hi;
    }
    _build(word - cfg.behind < 0 ? 0 : word - cfg.behind);
    final lo = word - 2, hi = word + cfg.anchorSlack;
    _d = [
      for (var j = 0; j < _d.length; j++) lo <= _posOf(j) && _posOf(j) <= hi ? 0.0 : cfg.resyncCost,
    ];
    _applySkips(_d);
    _ring = [0.0];
    _state = const WordState(null, WordStatus.uncertain, 0.0);
    return _state;
  }

  /// The imam has been silent a long time (rukuʿ, sujud, between rakʿahs).
  /// He may now start anything, al-Fatiha above all, whose first letters fit
  /// almost anywhere: nothing is highlighted again until [WordTrackerConfig.confirm]
  /// letters agree with the text.
  WordState pause() {
    _resume = config.confirm;
    if (_state.status == WordStatus.tracking) {
      _state = WordState(_state.word, WordStatus.uncertain, _state.confidence, _state.basmala);
    }
    return _state;
  }

  /// New tokens from the speech model, in order (any text: normalized to letters).
  WordState feed(Iterable<String> tokens) {
    for (final token in tokens) {
      for (final rune in normalize(token).replaceAll(' ', '').runes) {
        if (_anchored) _step(String.fromCharCode(rune));
      }
    }
    return _state;
  }

  // -- the expected text --------------------------------------------------

  static int _key(int pos, bool basmala, int k) => (pos * 2 + (basmala ? 1 : 0)) * 64 + k;

  void _build(int w0) {
    final w1 = w0 + config.behind + config.ahead < _end ? w0 + config.behind + config.ahead : _end;
    final letters = <String>[], weak = <bool>[], pos = <int>[], bas = <int>[], keys = <int>[];
    final starts = <int>[], skips = <int, int>{};

    void addWord(String text, int p, int verse, int k0) {
      final chars = [for (final r in text.runes) String.fromCharCode(r)];
      for (var k = 0; k < chars.length; k++) {
        final ch = chars[k];
        final sunLam = k == 1 && chars[0] == 'ا' && ch == 'ل' && chars.length > 2 && _sun.contains(chars[2]);
        letters.add(ch);
        weak.add(_weak.contains(ch) || sunLam);
        pos.add(p);
        bas.add(verse);
        keys.add(_key(p, verse != 0, k0 + k));
      }
    }

    for (var p = w0; p < w1; p++) {
      final verse = _basmalaAt[p];
      if (verse != null) {
        final begin = letters.length;
        var k0 = 0;
        for (final w in _basmalaWords) {
          addWord(w, p - 1, verse, k0);
          k0 += w.runes.length;
        }
        skips[letters.length] = begin;
      }
      starts.add(letters.length);
      addWord(index.words[p], p, 0, 0);
    }

    _letters = letters;
    _weakAt = weak;
    _pos = pos;
    _bas = bas;
    _keys = keys;
    _starts = starts;
    _skips = skips;
    _w0 = w0;
    _w1 = w1;
    _d = List.filled(letters.length + 1, config.resyncCost);
  }

  /// Stream position after [j] letters: the word of the last letter consumed.
  int _posOf(int j) => j > 0 ? _pos[j - 1] : _w0 - 1;

  void _applySkips(List<double> d) {
    for (final e in _skips.entries) {
      if (d[e.value] < d[e.key]) d[e.key] = d[e.value];
    }
  }

  /// Slide the window forward, keeping each letter's cost.
  void _rebase(int w0) {
    final old = {for (var j = 0; j < _keys.length; j++) _keys[j]: j + 1};
    final oldD = _d;
    _build(w0);
    final cap = config.resyncCost;
    _d = [cap, for (final k in _keys) old.containsKey(k) ? oldD[old[k]!] : cap];
  }

  // -- one heard letter ---------------------------------------------------

  void _step(String u) {
    final cfg = config;
    final d = _d, ref = _letters, weak = _weakAt;
    final ins = _weak.contains(u) ? cfg.weakInsCost : cfg.insCost;
    final next = List<double>.filled(d.length, 0.0);
    next[0] = d[0] + ins;
    for (var j = 1; j < d.length; j++) {
      final r = ref[j - 1];
      final double sub;
      if (r == u) {
        sub = 0.0;
      } else if (_similar.contains('$r$u')) {
        sub = cfg.similarCost;
      } else {
        sub = cfg.subCost;
      }
      var best = d[j - 1] + sub;
      var x = d[j] + ins;
      if (x < best) best = x;
      x = next[j - 1] + (weak[j - 1] ? cfg.weakDelCost : cfg.delCost);
      if (x < best) best = x;
      final begin = _skips[j];
      if (begin != null && next[begin] < best) best = next[begin];
      next[j] = best;
    }

    var low = next[0];
    for (final v in next) {
      if (v < low) low = v;
    }
    _total += low;
    for (var j = 0; j < next.length; j++) {
      next[j] -= low;
    }
    final b = _best(next);
    for (final s in _starts) {
      if (s >= b) break;
      if (cfg.backCost < next[s]) next[s] = cfg.backCost;
    }
    for (var j = 0; j < next.length; j++) {
      if (next[j] > cfg.resyncCost) next[j] = cfg.resyncCost;
    }
    _applySkips(next);
    _d = next;

    _lettersSeen++;
    _ring.add(_total);
    if (_ring.length > cfg.errorWindow + 1) _ring.removeAt(0);
    // Already at the last letter of the window before this one: this letter
    // is past the end of the text (after al-Fatiha: "amin", then his surah).
    final beyond = b == next.length - 1 && _prevBest == b;
    _prevBest = b;
    _display(b, beyond);
  }

  /// Cheapest j; on a tie the one nearest the shown word, then the earliest.
  int _best(List<double> d) {
    var best = 0;
    int? bestGap;
    for (var j = 0; j < d.length; j++) {
      if (j > 0 && d[j] > d[best]) continue;
      final gap = _shown != null ? (_posOf(j) - _shown!).abs() : 0;
      if (j == 0 || d[j] < d[best] || gap < bestGap!) {
        best = j;
        bestGap = gap;
      }
    }
    return best;
  }

  // -- display policy -----------------------------------------------------

  void _display(int b, bool beyond) {
    final cfg = config;
    final d = _d;
    final here = _posOf(b);
    var margin = cfg.resyncCost;
    for (var j = 0; j < d.length; j++) {
      if ((_posOf(j) - here).abs() > 2 && d[j] - d[b] < margin) margin = d[j] - d[b];
    }
    final k = _ring.length - 1;
    final error = k > 0 ? (_ring.last - _ring.first) / k : 0.0;
    final burst = _ring.last - _ring[_ring.length - 1 - (k < cfg.burst ? k : cfg.burst)];
    final ok = error <= cfg.maxError &&
        burst < cfg.burstCost &&
        margin >= cfg.minMargin &&
        _lettersSeen >= cfg.minLetters &&
        !beyond;
    _okRun = ok ? _okRun + 1 : 0;
    _unsure = ok ? 0 : _unsure + 1;
    if (_resume > 0) _resume = ok ? _resume - 1 : cfg.confirm;

    if (ok) {
      final shown = _shown;
      if (shown == null) {
        if (_okRun >= cfg.confirm) _show(here);
      } else if (0 <= here - shown && here - shown <= 2) {
        _show(here);
      } else {
        final pending = _pending;
        if (pending != null && (here - pending).abs() <= 1) {
          _pendingCount++;
        } else {
          _pending = here;
          _pendingCount = 1;
        }
        if (_pendingCount >= cfg.confirm) _show(here);
      }
    }

    final WordStatus status;
    if (_unsure >= cfg.lostAfter) {
      _shown = null;
      _pending = null;
      _pendingCount = 0;
      status = WordStatus.lost;
    } else if (ok && _shown == here && _resume == 0) {
      status = WordStatus.tracking;
    } else {
      status = WordStatus.uncertain;
    }
    final quality = 1.0 - error > 0.0 ? 1.0 - error : 0.0;
    final ratio = margin / cfg.backCost;
    final confidence = quality * (ratio < 1.0 ? ratio : 1.0);
    int? basmala;
    if (status == WordStatus.tracking && b > 0 && _bas[b - 1] != 0) basmala = _bas[b - 1];
    _state = WordState(basmala != null ? null : _shown, status, confidence, basmala);

    if (here - _w0 > cfg.behind + 5 && _w1 < _end) _rebase(here - cfg.behind);
  }

  void _show(int here) {
    _shown = here;
    _pending = null;
    _pendingCount = 0;
  }
}
