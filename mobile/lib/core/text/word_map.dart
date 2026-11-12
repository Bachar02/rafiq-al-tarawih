/// Which displayed Uthmani word is the word tracker's word?
///
/// The engine follows Simple Clean words (the index's word stream); the reader
/// shows Uthmani text, which splits a few words differently (the vocative:
/// Uthmani يٰٓأَيُّهَا is Simple Clean يا ايها). A port of
/// `engine/src/rafiq/word_truth.py` `map_verse` (checked against it on every
/// ayah, test/core/word_map_test.dart): a monotone alignment of the two word
/// lists by their letters. When an ayah's alignment is not convincing, there
/// is no answer and nothing is highlighted.
library;

import '../engine/matcher.dart' show levenshteinSimilarity;
import 'normalize.dart';
import 'quran_display.dart';

/// A token of only pause marks and other small signs: not a word.
final _markOnly = RegExp('^[ؐ-ؚۖ-ۭ࣓-ࣿ]+\$');

/// The Uthmani words, as quran-align and Python number them: the text split
/// on spaces, pause marks and other mark-only tokens left out.
List<String> uthmaniWords(String uthmani) => [
      for (final t in uthmani.split(' '))
        if (t.isNotEmpty && !_markOnly.hasMatch(t)) t
    ];

/// Word groupings tried, cheapest first, and what each costs beyond its letters.
const _moves = [(1, 1, 0.0), (1, 2, 0.05), (2, 1, 0.05), (1, 3, 0.1), (3, 1, 0.1), (2, 2, 0.15)];

/// Below this, a group's letters are too unlike to trust the mapping.
const minWordSimilarity = 0.5;

class WordMap {
  const WordMap(this.groups, this.worst);

  static const none = WordMap([], 0.0);

  /// (Uthmani word indices, Simple Clean word indices), in order.
  final List<(List<int>, List<int>)> groups;

  /// The lowest letter similarity of any group (0..1).
  final double worst;

  bool get ok => worst >= minWordSimilarity;

  /// The Uthmani word that Simple Clean word [index] is in, or null.
  int? uthmaniOf(int index) {
    if (!ok) return null;
    for (final (u, ours) in groups) {
      if (ours.contains(index)) return u.first;
    }
    return null;
  }
}

/// Align one ayah's Uthmani words with its Simple Clean words.
WordMap mapVerse(List<String> uthmani, List<String> ours) {
  final u = [for (final w in uthmani) normalize(w).replaceAll(' ', '')];
  final n = u.length, m = ours.length;
  const inf = double.infinity;
  final cost = List.generate(n + 1, (_) => List<double>.filled(m + 1, inf));
  final back = List.generate(n + 1, (_) => List<(int, int)?>.filled(m + 1, null));
  cost[0][0] = 0.0;
  String join(List<String> words, int from, int count) => words.sublist(from, from + count).join();
  for (var i = 0; i <= n; i++) {
    for (var j = 0; j <= m; j++) {
      if (cost[i][j] == inf) continue;
      for (final (a, b, extra) in _moves) {
        if (i + a > n || j + b > m) continue;
        final sim = levenshteinSimilarity(join(u, i, a), join(ours, j, b));
        final c = cost[i][j] + (1.0 - sim) + extra;
        if (c < cost[i + a][j + b]) {
          cost[i + a][j + b] = c;
          back[i + a][j + b] = (a, b);
        }
      }
    }
  }
  if (cost[n][m] == inf) return WordMap.none;
  final groups = <(List<int>, List<int>)>[];
  var worst = 1.0;
  var i = n, j = m;
  while (i > 0 || j > 0) {
    final (a, b) = back[i][j]!;
    i -= a;
    j -= b;
    final sim = levenshteinSimilarity(join(u, i, a), join(ours, j, b));
    if (sim < worst) worst = sim;
    groups.add(([for (var k = i; k < i + a; k++) k], [for (var k = j; k < j + b; k++) k]));
  }
  return WordMap(groups.reversed.toList(), worst);
}

/// The ayah's displayed text cut at its spaces ([displayAyahText] keeps pause
/// marks with their word), and which of the pieces is each Uthmani word.
/// Joining the pieces with single spaces gives the displayed text back.
({List<String> pieces, List<int> wordPiece}) displayPieces(String uthmani) {
  final pieces = displayAyahText(uthmani).split(' ');
  final wordPiece = <int>[];
  for (var p = 0; p < pieces.length; p++) {
    final letters = pieces[p].replaceAll(nbsp, ' ').split(' ').where((t) => t.isNotEmpty && !_markOnly.hasMatch(t));
    if (letters.isNotEmpty) wordPiece.add(p);
  }
  return (pieces: pieces, wordPiece: wordPiece);
}

/// Per-ayah answers, computed once each: the reader asks for one ayah at a time.
class DisplayWordMap {
  final _cache = <int, ({WordMap map, List<int> wordPiece, int words})>{};

  /// The displayed piece of verse [verseId] that holds its Simple Clean word
  /// [index], or null when the ayah's mapping cannot be trusted.
  int? pieceOf({required int verseId, required String uthmani, required String simple, required int index}) {
    final entry = _cache[verseId] ??= _build(uthmani, simple);
    final u = entry.map.uthmaniOf(index);
    if (u == null || entry.wordPiece.length != entry.words || u >= entry.wordPiece.length) return null;
    return entry.wordPiece[u];
  }

  static ({WordMap map, List<int> wordPiece, int words}) _build(String uthmani, String simple) {
    final words = uthmaniWords(uthmani);
    return (map: mapVerse(words, tokenize(simple)), wordPiece: displayPieces(uthmani).wordPiece, words: words.length);
  }
}
