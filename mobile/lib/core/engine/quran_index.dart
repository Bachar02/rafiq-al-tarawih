/// The Quran as a single normalized word stream, plus an inverted index over
/// it. A port of `engine/src/rafiq/matching/index.py`.
///
/// Treating the whole text as one stream (about 78,000 words) is what lets a
/// query that spans the end of one ayah and the start of the next match
/// naturally: there is no ayah boundary in the stream, only [verseAt].
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../text/normalize.dart';

/// Normalized word stream with postings and IDF weights. Immutable.
class QuranIndex {
  QuranIndex._(this.words, this._wordVerse, this._verseStart, this.postings, this.vocab, this.idf, this.verseCount,
      this._surahStarts);

  /// [verseTexts] in verse-id order (Simple Clean): verse id `i + 1` is
  /// `verseTexts[i]`. [surahStarts]: each surah's first verse id, in order
  /// (the Python index has the whole Quran; the tracker's tie report needs
  /// the surahs).
  factory QuranIndex(List<String> verseTexts, {required List<int> surahStarts}) {
    if (surahStarts.isEmpty || surahStarts.first != 1) throw ArgumentError('surahStarts must begin with verse 1');
    for (var i = 1; i < surahStarts.length; i++) {
      if (surahStarts[i] <= surahStarts[i - 1] || surahStarts[i] > verseTexts.length) {
        throw ArgumentError('surahStarts must rise within the verses');
      }
    }
    final words = <String>[];
    final wordVerse = <int>[];
    final verseStart = Int32List(verseTexts.length + 2); // [count + 1] is a sentinel
    for (var i = 0; i < verseTexts.length; i++) {
      verseStart[i + 1] = words.length;
      final tokens = tokenize(verseTexts[i]);
      words.addAll(tokens);
      for (var t = 0; t < tokens.length; t++) {
        wordVerse.add(i + 1);
      }
    }
    verseStart[verseTexts.length + 1] = words.length;

    // Insertion order (first occurrence), as Python's dict keeps it.
    final postings = <String, List<int>>{};
    for (var pos = 0; pos < words.length; pos++) {
      (postings[words[pos]] ??= []).add(pos);
    }
    final vocab = postings.keys.toList()..sort();
    final n = verseTexts.length;
    final idf = <String, double>{};
    for (final e in postings.entries) {
      final verses = <int>{for (final p in e.value) wordVerse[p]};
      idf[e.key] = math.log(1 + n / verses.length);
    }
    return QuranIndex._(
      List.unmodifiable(words),
      Int32List.fromList(wordVerse),
      verseStart,
      Map.unmodifiable({for (final e in postings.entries) e.key: List<int>.unmodifiable(e.value)}),
      List.unmodifiable(vocab),
      Map.unmodifiable(idf),
      n,
      Int32List.fromList(surahStarts),
    );
  }

  final List<String> words;
  final Int32List _wordVerse;
  final Int32List _verseStart;
  final Map<String, List<int>> postings;

  /// The distinct words, sorted.
  final List<String> vocab;
  final Map<String, double> idf;
  final int verseCount;
  final Int32List _surahStarts;

  int get length => words.length;

  /// The surah (1-based) of verse [verseId].
  int surahOf(int verseId) {
    var lo = 0, hi = _surahStarts.length; // the last start <= verseId
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (_surahStarts[mid] <= verseId) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo + 1;
  }

  /// Stream range `[start, end)` covered by one verse.
  (int, int) verseSpan(int verseId) => (_verseStart[verseId], _verseStart[verseId + 1]);

  /// Verse id of the word at stream position [pos] (clamped to the stream).
  int verseAt(int pos) => _wordVerse[pos.clamp(0, words.length - 1)];

  String text(int start, int end) => words.sublist(math.max(start, 0), math.min(end, words.length)).join(' ');
}
