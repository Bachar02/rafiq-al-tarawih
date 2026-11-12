import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/text/normalize.dart';
import 'package:rafiq/core/text/quran_display.dart';
import 'package:rafiq/core/text/word_map.dart';

import '../support/fakes.dart';

/// The Uthmani <-> Simple Clean word mapping (word highlighting), on every
/// ayah, against the Python reference (engine/src/rafiq/word_truth.py).
void main() {
  final quran = loadQuran();
  final golden = jsonDecode(File('test/golden/word_map.json').readAsStringSync()) as Map<String, dynamic>;
  final expected = {
    for (final c in (golden['not_identity'] as List).cast<List<dynamic>>()) c[0] as int: c,
  };

  test('all 6,236 ayahs map, exactly as the Python engine maps them', () {
    expect(golden['ayahs'], 6236);
    expect(golden['ok'], 6236);
    var ok = 0, checked = 0;
    for (final v in quran.verses) {
      final m = mapVerse(uthmaniWords(v.uthmani), tokenize(v.text));
      if (m.ok) ok++;
      final want = expected[v.id];
      final groups = [
        for (final (u, s) in m.groups) [u, s]
      ];
      if (want == null) {
        // Not in the golden file: every word maps to its own.
        expect(m.groups.every((g) => g.$1.length == 1 && g.$2.length == 1 && g.$1.first == g.$2.first), isTrue,
            reason: '${v.surah}:${v.ayah}');
      } else {
        expect(groups, want[1], reason: '${v.surah}:${v.ayah}');
        expect(m.worst, closeTo((want[2] as num).toDouble(), 1e-9), reason: '${v.surah}:${v.ayah}');
      }
      checked++;
    }
    expect(checked, 6236);
    expect(ok, 6236, reason: 'every ayah is trusted');
  });

  test('every Uthmani word is one displayed piece, in order, and the text is unchanged', () {
    for (final v in quran.verses) {
      final words = uthmaniWords(v.uthmani);
      final (:pieces, :wordPiece) = displayPieces(v.uthmani);
      expect(pieces.join(' '), displayAyahText(v.uthmani), reason: 'nothing added or lost');
      expect(wordPiece.length, words.length, reason: '${v.surah}:${v.ayah}');
      for (var k = 0; k < words.length; k++) {
        expect(normalize(pieces[wordPiece[k]]).replaceAll(' ', ''), normalize(words[k]).replaceAll(' ', ''),
            reason: '${v.surah}:${v.ayah} word $k');
      }
    }
  });

  test('the vocative: Simple Clean يا and ايها are one displayed word', () {
    final v = quran.verse(quran.surah(2).firstVerseId + 20); // 2:21
    final map = DisplayWordMap();
    final a = map.pieceOf(verseId: v.id, uthmani: v.uthmani, simple: v.text, index: 0);
    final b = map.pieceOf(verseId: v.id, uthmani: v.uthmani, simple: v.text, index: 1);
    final c = map.pieceOf(verseId: v.id, uthmani: v.uthmani, simple: v.text, index: 2);
    expect(a, 0);
    expect(b, 0);
    expect(c, 1);
  });

  test('a mapping that does not fit gives no word to highlight', () {
    final m = mapVerse(['كتب'], ['الرحمن', 'الرحيم']);
    expect(m.ok, isFalse);
    expect(m.uthmaniOf(0), isNull);
  });
}
