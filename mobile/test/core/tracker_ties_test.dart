import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/engine/matcher.dart';
import 'package:rafiq/core/engine/tracker.dart';
import 'package:rafiq/core/text/normalize.dart';
import 'package:rafiq/data/quran.dart';

import '../support/fakes.dart';

/// The tie report (PLAN.md §37): while a position is unconfirmed, every ayah
/// repeated text fits as well as the best (`tied`), and whether that set can
/// be relied on (`tieTrusted`). The same cases as engine/tests/test_tracking.py;
/// the golden files check Python and Dart agree on every state.
void main() {
  late Quran quran;
  late QuranMatcher matcher;
  late Tracker tracker;
  int vid(int surah, int ayah) => quran.verseId(surah, ayah)!;
  Set<int> surahsOf(List<int> verses) => {for (final v in verses) quran.verse(v).surah};
  TrackerState alone(String text) => Tracker(matcher).update(text);

  const refrain = 'فبأي آلاء ربكما تكذبان';

  setUpAll(() {
    quran = loadQuran();
    matcher = QuranMatcher(indexOf(quran));
  });
  setUp(() => tracker = Tracker(matcher));

  test('the shortlist starts with exactly the top k; the cap says what it left out', () {
    for (final text in [refrain, 'يا أيها الذين آمنوا', 'بلى مربي للقسط', 'والضحى والليل إذا سجى']) {
      final tokens = tokenize(text);
      final all = matcher.matchAll(tokens);
      expect(all.votes.length, all.matches.length);
      for (final k in [1, 5, 8]) {
        expect([for (final m in matcher.matchTokens(tokens, k: k)) (m.start, m.end)],
            [for (final m in all.matches.take(k)) (m.start, m.end)]);
      }
    }
    final many = matcher.matchAll(tokenize('يا أيها الذين آمنوا')); // 89 copies
    expect(many.cut, isNotNull);
  });

  test('Ar-Rahman: all 31 copies of the refrain, one surah, trusted', () {
    final state = alone(refrain);
    final copies = [
      for (final v in quran.verses)
        if (v.surah == 55 && tokenize(v.text).join(' ') == tokenize(refrain).join(' ')) v.id
    ];
    expect(copies.length, 31);
    expect(state.verseId, isNull);
    expect(state.tied, copies);
    expect(state.tieTrusted, isTrue);
    expect(state.alternatives.length, 3, reason: 'the display list is unchanged');
  });

  test('repeated ayahs close by: one trusted surah', () {
    for (final (text, ayahs) in [
      ('ثم أتبع سببا', [(18, 89), (18, 92)]),
      ('ولا أنتم عابدون ما أعبد', [(109, 3), (109, 5)]),
      ('وأذنت لربها وحقت', [(84, 2), (84, 5)]),
      ('وإن مع العسر يسرا', [(94, 5), (94, 6)]), // a misheard word between two copies
    ]) {
      final state = alone(text);
      expect(state.tied, [for (final (s, a) in ayahs) vid(s, a)], reason: text);
      expect(state.tieTrusted, isTrue, reason: text);
    }
  });

  test('a phrase in three surahs: a trusted tie across them', () {
    final state = alone('فاتقوا الله وأطيعون');
    expect(surahsOf(state.tied), {3, 26, 43});
    expect(state.tieTrusted, isTrue);
  });

  test('ties that would not have been shown are not trusted', () {
    for (final text in ['كذلك نجزي المحسنين', 'ويل يومئذ للمكذبين', 'إن الله غفور رحيم']) {
      final state = alone(text);
      expect(state.tied.length, greaterThanOrEqualTo(2), reason: text);
      expect(state.tieTrusted, isFalse, reason: text);
    }
  });

  test('89 copies, beyond the cap: incomplete, never trusted', () {
    final state = alone('يا أيها الذين آمنوا');
    expect(state.tied.length, lessThan(89));
    expect(state.tieTrusted, isFalse);
  });

  test('garbled previews and short chunks are not trusted', () {
    for (final text in ['بلى مربي للقسط', 'بما ما ربي', 'ذلك وما']) {
      expect(alone(text).tieTrusted, isFalse, reason: text);
    }
  });

  test('a one-word chunk is a miss and reports no tie; unique text neither', () {
    final miss = alone('الم');
    expect(miss.evidence, isFalse);
    expect(miss.tied, isEmpty);
    expect(miss.tieTrusted, isFalse);
    final unique = alone('والضحى والليل إذا سجى');
    expect(unique.verseId, isNotNull);
    expect(unique.tied, isEmpty);
    expect(unique.tieTrusted, isFalse);
  });

  test('the tie is held through a miss and cleared once a position is accepted', () {
    final first = tracker.update(refrain);
    final held = tracker.update('zzz');
    expect(held.evidence, isFalse);
    expect(held.tied, first.tied);
    expect(held.tieTrusted, isTrue);
    final accepted = tracker.update('يسأله من في السماوات والأرض كل يوم هو في شأن');
    expect(accepted.verseId, vid(55, 29));
    expect(accepted.tied, isEmpty);
    expect(accepted.tieTrusted, isFalse);
  });

  test("the user's position clears the tie", () {
    expect(tracker.update(refrain).tied, isNotEmpty);
    final state = tracker.setPosition(vid(55, 47));
    expect(state.tied, isEmpty);
    expect(state.tieTrusted, isFalse);
  });

  test('a far jump into repeated text reports the tie while holding the position', () {
    for (final t in ['والضحى والليل إذا سجى', 'ما ودعك ربك وما قلى']) {
      tracker.update(t);
    }
    final state = tracker.update(refrain);
    expect(state.verseId, vid(93, 3));
    expect(surahsOf(state.tied), {55});
    expect(state.tieTrusted, isTrue);
  });

  test('no tie where the screen already is; previews change nothing', () {
    tracker.setPosition(vid(55, 12));
    final state = tracker.update(refrain);
    expect(state.verseId, vid(55, 13));
    expect(state.tied, isEmpty);
    final fresh = Tracker(matcher);
    expect(fresh.preview(refrain).tied.length, 31);
    expect(fresh.state.tied, isEmpty);
  });

  test('inside a lock, the tie is the locked surah alone', () {
    final s = quran.surah(26);
    tracker.lock(s.firstVerseId, s.lastVerseId);
    final state = tracker.update('فاتقوا الله وأطيعون');
    expect(surahsOf(state.tied), {26});
    expect(state.tieTrusted, isTrue);
  });
}
