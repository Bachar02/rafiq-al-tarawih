import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/engine/matcher.dart';
import 'package:rafiq/core/engine/tracker.dart';
import 'package:rafiq/core/engine/word_follower.dart';

import '../support/fakes.dart';

/// The word follower: the word tracker driven by the speech model's partial
/// and final transcripts, anchored by the (unchanged) ayah tracker.
void main() {
  final quran = loadQuran();
  final index = indexOf(quran);
  final matcher = QuranMatcher(index);
  final basmala = [
    for (final s in quran.surahs)
      if (s.hasBasmala) s.firstVerseId
  ];

  test('on real recorded Whisper output it does exactly what was evaluated in Python', () {
    final cases =
        (jsonDecode(File('test/golden/word_follow.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    var events = 0, lit = 0;
    for (final c in cases) {
      final tracker = Tracker(matcher);
      final follower = WordFollower(index, basmalaVerses: basmala);
      final want = (c['words'] as List).cast<int?>();
      final input = (c['events'] as List).cast<List<dynamic>>();
      for (var i = 0; i < input.length; i++) {
        final [text as String, isFinal as bool, start as num, end as num] = input[i];
        final ayah = isFinal ? tracker.update(text) : tracker.preview(text);
        final got =
            follower.onChunk(text: text, isFinal: isFinal, start: start.toDouble(), end: end.toDouble(), ayah: ayah);
        expect(got?.position, want[i], reason: '${c['name']}, event $i: "$text"');
        events++;
        if (got != null) lit++;
      }
    }
    expect(events, greaterThan(900));
    expect(lit, greaterThan(400), reason: 'words are highlighted on real output');
  });

  group('scenarios', () {
    late Tracker tracker;
    late WordFollower follower;
    var clock = 0.0;

    setUp(() {
      tracker = Tracker(matcher);
      follower = WordFollower(index, basmalaVerses: basmala);
      clock = 0.0;
    });

    String text(int from, int to) => index.words.sublist(from, to).join(' ');

    /// One breath: partials of its growing prefix, then the final. Returns
    /// what each transcript made the follower show (the final last).
    List<FollowedWord?> breath(String said, {double gap = 0.5, List<String>? partials}) {
      final start = clock + gap;
      final words = said.split(' ');
      final end = start + 0.4 * words.length;
      clock = end;
      final out = <FollowedWord?>[];
      final previews = partials ?? [for (var n = 2; n < words.length; n += 2) words.sublist(0, n).join(' ')];
      for (final (k, p) in previews.indexed) {
        final ayah = tracker.preview(p);
        out.add(follower.onChunk(text: p, isFinal: false, start: start, end: start + 0.5 * (k + 1), ayah: ayah));
      }
      final ayah = tracker.update(said);
      out.add(follower.onChunk(text: said, isFinal: true, start: start, end: end, ayah: ayah));
      return out;
    }

    /// Recite verse [verseId] in breaths of [size] words; the final of each.
    List<FollowedWord?> recite(int verseId, {int size = 6}) {
      final (lo, hi) = index.verseSpan(verseId);
      return [for (var p = lo; p < hi; p += size) breath(text(p, p + size > hi ? hi : p + size)).last];
    }

    int lastWordOf(int verseId) => index.verseSpan(verseId).$2 - 1;

    test('finals commit, and follow the imam word by word once the ayah is found', () {
      final v = quran.surah(2).firstVerseId + 254; // 2:255, a long ayah
      recite(v - 1);
      final finals = recite(v);
      expect(finals.last?.position, lastWordOf(v));
      expect(finals.last?.verseId, v);
    });

    void fresh() {
      tracker = Tracker(matcher);
      follower = WordFollower(index, basmalaVerses: basmala);
      clock = 0;
    }

    test('a misheard partial is replaced by the next one, not added to it', () {
      final v = quran.surah(2).firstVerseId + 254;
      final (lo, _) = index.verseSpan(v);
      final said = text(lo, lo + 6);
      recite(v - 1);
      final revised = breath(said, partials: ['ترره بعيد', 'كلمات لا علاقة لها', text(lo, lo + 4)]);
      fresh();
      recite(v - 1);
      final plain = breath(said, partials: [text(lo, lo + 4)]);
      expect(revised.last?.position, plain.last?.position, reason: 'the final is the same whatever the partials said');
      expect(revised.last?.position, lo + 5);
    });

    test('a partial previews without committing', () {
      final v = quran.surah(2).firstVerseId + 254;
      recite(v - 1);
      final before = follower.committed.word;
      final (lo, _) = index.verseSpan(v);
      final ayah = tracker.preview(text(lo, lo + 4));
      final preview =
          follower.onChunk(text: text(lo, lo + 4), isFinal: false, start: clock + 0.5, end: clock + 2, ayah: ayah);
      expect(preview?.position, lo + 3, reason: 'the preview follows the words heard');
      expect(follower.committed.word, before, reason: 'nothing is committed until the final');
    });

    test('the imam goes back to repeat: the highlight follows him back', () {
      final v = quran.surah(2).firstVerseId + 254;
      recite(v - 1);
      final (lo, _) = index.verseSpan(v);
      breath(text(lo, lo + 6));
      breath(text(lo + 6, lo + 12));
      final back = breath(text(lo + 8, lo + 14)).last; // back four words, then on
      expect(back?.position, lo + 13);
      final again = breath(text(lo + 4, lo + 10)).last; // further back
      expect(again?.position, lo + 9);
    });

    test('al-Fatiha at a new rakʿah, then back to the surah', () {
      final kahf = quran.surah(18).firstVerseId;
      recite(kahf);
      recite(kahf + 1);
      expect(recite(kahf + 2).last?.verseId, kahf + 2);
      // Rukuʿ and sujud: a long silence, then al-Fatiha.
      final (f0, f1) = (index.verseSpan(1).$1, index.verseSpan(7).$2);
      final fatiha = [breath(text(f0, f0 + 4), gap: 40).last];
      for (var p = f0 + 4; p < f1; p += 5) {
        fatiha.add(breath(text(p, p + 5 > f1 ? f1 : p + 5)).last);
      }
      expect(fatiha.last?.verseId, 7, reason: 'al-Fatiha is followed word by word');
      // The imam returns to his surah.
      final resumed = [...recite(kahf + 3), ...recite(kahf + 4)];
      expect(resumed.last?.verseId, kahf + 4);
      expect(resumed.last?.position, lastWordOf(kahf + 4));
    });

    test('the basmala before a surah, recited aloud or not', () {
      final ikhlas = quran.surah(112).firstVerseId, falaq = quran.surah(113).firstVerseId;
      final (b0, b1) = index.verseSpan(1); // the basmala's words
      for (final aloud in [true, false]) {
        fresh();
        for (var v = ikhlas; v < falaq; v++) {
          recite(v, size: 8);
        }
        final shown = <FollowedWord?>[];
        if (aloud) shown.addAll(breath(text(b0, b1)));
        shown.addAll(recite(falaq));
        shown.addAll(recite(falaq + 1));
        expect(shown.last?.position, lastWordOf(falaq + 1), reason: aloud ? 'aloud' : 'silent');
        for (final w in shown.whereType<FollowedWord>()) {
          expect(w.verseId == 1 || (w.verseId >= ikhlas && w.verseId <= falaq + 1), isTrue,
              reason: 'never a word outside the passage (${w.verseId})');
        }
      }
    });

    test('after a long pause, the first letters only confirm', () {
      final v = quran.surah(2).firstVerseId + 254;
      recite(v - 1);
      final (lo, _) = index.verseSpan(v);
      breath(text(lo, lo + 6));
      // A long silence, then a very short partial ("الله" is 4 letters, or fewer).
      final start = clock + 5;
      final short = index.words[lo + 6].substring(0, 2);
      final ayah = tracker.preview(short);
      final first = follower.onChunk(text: short, isFinal: false, start: start, end: start + 0.4, ayah: ayah);
      expect(first, isNull, reason: 'not highlighted on two letters after a pause');
      clock = start;
      final rest = breath(text(lo + 6, lo + 12), gap: 0.1).last;
      expect(rest?.position, lo + 11);
    });

    test('a far jump: the ayah tracker finds the new place and the words follow it there', () {
      final v = quran.surah(2).firstVerseId + 254;
      recite(v - 1);
      recite(v);
      final far = quran.surah(36).firstVerseId + 20; // Ya-Sin 36:21
      final after = [...recite(far), ...recite(far + 1), ...recite(far + 2)];
      expect(after.last?.verseId, far + 2);
      expect(after.last?.position, lastWordOf(far + 2));
    });

    test('lost: noise that is not the Quran hides the word', () {
      final v = quran.surah(2).firstVerseId + 254;
      recite(v - 1);
      expect(recite(v).last, isNotNull);
      final noise = [
        for (var k = 0; k < 6; k++) breath('سبحان ربي العظيم سمع الله لمن حمده ربنا ولك الحمد').last,
      ];
      expect(noise.last, isNull, reason: 'the word tracker is no longer sure');
    });

    test('"the imam is here": the words follow from where the user said', () {
      final v = quran.surah(19).firstVerseId + 9; // Maryam 19:10
      follower.setPosition(v);
      tracker.setPosition(v);
      final (lo, _) = index.verseSpan(v);
      final shown = breath(text(lo, lo + 6)).last;
      expect(shown?.position, lo + 5);
    });
  });
}
