/// Follows the imam word by word from the speech model's transcripts, next to
/// the ayah tracker. Exactly what `engine/src/rafiq/word_eval.py`
/// `replay_words` evaluated on real recordings (PLAN.md §30–31), kept equal
/// by a golden test; no prediction.
///
/// * **Partials are previews.** Each live partial re-transcribes the whole
///   breath so far and may revise it, so it is fed to a *copy* of the word
///   tracker as it stood when the breath began; the next one starts again
///   from there. Only the final transcript at the pause is committed.
/// * **Anchoring** comes from the ayah tracker, unchanged: after a final, the
///   word tracker is anchored at the ayah tracker's word when it is idle or
///   lost, or when the two disagree by more than one ayah (al-Fatiha at each
///   rakʿah, a far jump, the imam going back further than it can follow).
/// * **A long pause** between breaths (rukuʿ, sujud) makes the word tracker
///   re-confirm before it highlights again.
library;

import 'quran_index.dart';
import 'tracker.dart';
import 'word_tracker.dart';

/// The word being recited, when the word tracker is sure of it.
class FollowedWord {
  const FollowedWord({required this.position, required this.verseId, required this.index});

  /// Stream position (all of the Quran as one word stream).
  final int position;
  final int verseId;

  /// Index of the word in its ayah (Simple Clean words, as the index has them).
  final int index;
}

class WordFollower {
  WordFollower(
    this.quranIndex, {
    required Iterable<int> basmalaVerses,
    this.config = const WordTrackerConfig(),
    this.pauseAfter = 2.5,
  }) : _base = WordTracker(quranIndex, basmalaVerses: basmalaVerses, config: config);

  final QuranIndex quranIndex;
  final WordTrackerConfig config;

  /// Seconds between one breath's end and the next one's start that count as
  /// a long pause.
  final double pauseAfter;

  final WordTracker _base;
  double? _breath; // start of the breath being previewed
  double? _lastEnd; // end of the last final

  /// The word tracker as committed (finals only).
  WordState get committed => _base.state;

  /// One transcript from the listener, after the ayah tracker has taken it
  /// ([ayah] is its state). Returns the word to highlight, or null.
  FollowedWord? onChunk({
    required String text,
    required bool isFinal,
    required double start,
    required double end,
    required TrackerState ayah,
  }) {
    if (start != _breath) {
      final last = _lastEnd;
      if (last != null && start - last > pauseAfter) _base.pause();
      _breath = start;
    }
    final work = isFinal ? _base : _base.copy();
    var state = work.feed([text]);
    if (isFinal) {
      _lastEnd = end;
      _breath = null; // the next transcript begins a new breath
      final at = ayah.word;
      if (ayah.status == TrackerStatus.tracking && at != null) {
        final mine = _base.state;
        final disagree = mine.word != null && (quranIndex.verseAt(mine.word!) - ayah.verseId!).abs() > 1;
        if (mine.status == WordStatus.idle || mine.status == WordStatus.lost || disagree) {
          state = _base.anchor(at);
        }
      }
    }
    return _shown(state);
  }

  /// The user said where the imam is: follow from the start of [verseId].
  void setPosition(int verseId) {
    _base.anchor(quranIndex.verseSpan(verseId).$1);
    _breath = null;
  }

  /// Audio was dropped (the phone fell behind): what comes next does not
  /// continue what was heard, so it must be confirmed afresh.
  void skipped() => _base.pause();

  /// Start again (a new session).
  void reset() {
    _base.reset();
    _breath = null;
    _lastEnd = null;
  }

  FollowedWord? _shown(WordState state) {
    final word = state.word;
    if (state.status != WordStatus.tracking || word == null) return null;
    final verse = quranIndex.verseAt(word);
    return FollowedWord(position: word, verseId: verse, index: word - quranIndex.verseSpan(verse).$1);
  }
}
