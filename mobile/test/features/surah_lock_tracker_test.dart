import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/engine/matcher.dart';
import 'package:rafiq/core/engine/tracker.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/data/quran.dart';
import 'package:rafiq/features/listen/surah_lock.dart';

import '../support/fakes.dart';

/// The following surah lock (PLAN.md §36) driving the real tracker, as the
/// on-device engine does: the app decides the window, the tracker gets ranges.
void main() {
  late Quran quran;
  late QuranMatcher matcher;

  setUpAll(() {
    quran = loadQuran();
    matcher = QuranMatcher(indexOf(quran));
  });

  int vid(int surah, int ayah) => quran.verseId(surah, ayah)!;
  String ref(int? verseId) => verseId == null ? '-' : '${quran.verse(verseId).surah}:${quran.verse(verseId).ayah}';

  /// Each ayah in breaths of at most 6 words, as the speech model hears them.
  List<String> breaths(int from, int to) => [
        for (var v = from; v <= to; v++)
          for (final words = quran.verse(v).text.split(' '), i = [0]; i[0] < words.length; i[0] += 6)
            words.sublist(i[0], (i[0] + 6).clamp(0, words.length)).join(' '),
      ];

  /// A session: the tracker, the app's lock, and following it after each result.
  ({Tracker tracker, Hint? Function() lock, void Function(Hint?) setLock, TrackerState Function(String) hear}) session(
      Hint? initial,
      {bool follow = true}) {
    final tracker = Tracker(matcher);
    Hint? lock;
    void setLock(Hint? l) {
      lock = l;
      final window = l == null ? null : SurahLock.window(l);
      switch (window) {
        case SurahRange(:final first, :final last):
          tracker.lock(quran.surah(first).firstVerseId, quran.surah(last).lastVerseId);
        case SurahHint(:final surah):
          tracker.lock(quran.surah(surah).firstVerseId, quran.surah(surah).lastVerseId);
        default:
          tracker.lock(null);
      }
    }

    setLock(initial);
    TrackerState hear(String text) {
      final s = tracker.update(text);
      final p = s.verseId == null ? null : quran.verse(s.verseId!);
      final heard = Heard(
        text: text,
        start: 0,
        end: 1,
        asrMs: 0,
        isFinal: true,
        state: TrackState(
          status: TrackStatus.values[s.status.index],
          position: p == null ? null : Position(verseId: p.id, surah: p.surah, ayah: p.ayah),
          evidence: s.evidence,
        ),
      );
      final moved = follow ? SurahLock.follow(lock, heard) : null;
      if (moved != null) setLock(moved);
      return s;
    }

    return (tracker: tracker, lock: () => lock, setLock: setLock, hear: hear);
  }

  test('the window: a surah and the next; the last surah alone; a juz as it is', () {
    expect(SurahLock.window(const SurahHint(2)), const SurahRange(2, 3));
    expect(SurahLock.window(const SurahHint(114)), const SurahRange(114, 114));
    expect(SurahLock.window(const JuzHint(30)), const JuzHint(30));
  });

  test('locked on Al-Baqarah, the imam continues into Aal-Imran: followed, not stuck', () {
    final s = session(const SurahHint(2));
    final states = [
      for (final b in [...breaths(vid(2, 283), vid(2, 286)), ...breaths(vid(3, 1), vid(3, 6))]) s.hear(b)
    ];
    // The last breath of 3:6 is two words: a miss. The last result with evidence:
    final last = states.lastWhere((st) => st.evidence);
    expect(ref(last.verseId), '3:6');
    expect(last.status, TrackerStatus.tracking);
    expect(s.lock(), const SurahHint(3));
    // Exactly what the tracker does with no lock at all.
    final free = session(null);
    final unlocked = [
      for (final b in [...breaths(vid(2, 283), vid(2, 286)), ...breaths(vid(3, 1), vid(3, 6))]) free.hear(b)
    ];
    expect([for (final st in states) st.verseId], [for (final st in unlocked) st.verseId]);
  });

  test('the old lock (one surah, never moved) was stuck at the boundary', () {
    final s = session(const SurahHint(2), follow: false);
    s.setLock(const SurahHint(2)); // the window is not used: lock the surah alone
    s.tracker.lock(quran.surah(2).firstVerseId, quran.surah(2).lastVerseId);
    TrackerState? last;
    for (final b in [...breaths(vid(2, 283), vid(2, 286)), ...breaths(vid(3, 1), vid(3, 6))]) {
      last = s.hear(b);
    }
    expect(quran.verse(last!.verseId!).surah, 2, reason: 'held in Al-Baqarah while the imam is in Aal-Imran');
    expect(last.status, isNot(TrackerStatus.tracking));
  });

  test('through several boundaries in a row: Al-Ikhlas, Al-Falaq, An-Nas', () {
    final s = session(const SurahHint(112));
    TrackerState? last;
    for (final b in breaths(vid(112, 1), vid(114, 6))) {
      last = s.hear(b);
    }
    expect(ref(last!.verseId), '114:6');
    expect(s.lock(), const SurahHint(114));
  });

  test('al-Fatiha between rakʿahs at the boundary changes nothing', () {
    final s = session(const SurahHint(2));
    for (final b in [...breaths(vid(2, 284), vid(2, 286)), ...breaths(1, 7)]) {
      s.hear(b);
    }
    expect(s.lock(), const SurahHint(2), reason: 'al-Fatiha never moves the lock');
    TrackerState? last;
    for (final b in breaths(vid(3, 1), vid(3, 4))) {
      last = s.hear(b);
    }
    expect(ref(last!.verseId), '3:4');
    expect(s.lock(), const SurahHint(3));
  });

  test('repeated words near the boundary: 3:2 opens like Ayat al-Kursi (2:255)', () {
    // After 2:286, the words of 3:2 are 3:2, not 2:255, which the window also holds.
    final s = session(const SurahHint(2));
    for (final b in [...breaths(vid(2, 284), vid(2, 286)), ...breaths(vid(3, 1), vid(3, 1))]) {
      s.hear(b);
    }
    final after = s.hear('الله لا إله إلا هو الحي القيوم');
    expect(ref(after.verseId), '3:2');
    expect(s.lock(), const SurahHint(3));
    // And at 2:254, the same words are 2:255: the lock stays on Al-Baqarah.
    final t = session(const SurahHint(2));
    for (final b in breaths(vid(2, 253), vid(2, 254))) {
      t.hear(b);
    }
    expect(ref(t.hear('الله لا إله إلا هو الحي القيوم').verseId), '2:255');
    expect(t.lock(), const SurahHint(2));
  });

  test('an incorrect far jump into the next surah does not move the lock', () {
    final s = session(const SurahHint(2));
    for (final b in breaths(vid(2, 283), vid(2, 284))) {
      s.hear(b);
    }
    final wrong = s.hear(breaths(vid(3, 150), vid(3, 150)).first); // far, inside the window, once
    expect(quran.verse(wrong.verseId!).surah, 2, reason: 'unconfirmed: the screen holds Al-Baqarah');
    expect(s.lock(), const SurahHint(2));
    final back = s.hear(breaths(vid(2, 285), vid(2, 285)).first);
    expect(ref(back.verseId), '2:285');
    expect(s.lock(), const SurahHint(2));
    // Outside the window: not even a candidate.
    expect(s.hear('قالوا يا موسى إما أن تلقي وإما أن نكون نحن الملقين').evidence, isFalse);
    expect(s.lock(), const SurahHint(2));
  });

  test('"the imam is here" elsewhere moves the lock with him; unlocking searches everywhere', () {
    final s = session(const SurahHint(2));
    for (final b in breaths(vid(2, 283), vid(2, 284))) {
      s.hear(b);
    }
    const at = Position(verseId: 503, surah: 4, ayah: 10); // 4:10
    expect(vid(4, 10), at.verseId);
    final moved = SurahLock.correct(s.lock(), at);
    expect(moved, const SurahHint(4));
    s.setLock(moved);
    s.tracker.setPosition(at.verseId);
    expect(ref(s.hear(breaths(vid(4, 11), vid(4, 11)).first).verseId), '4:11');
    s.setLock(null);
    final found = [for (final b in breaths(vid(7, 115), vid(7, 116))) s.hear(b)].last;
    expect(ref(found.verseId), '7:116');
  });

  test('without a lock, tracking is as before', () {
    final s = session(null);
    TrackerState? last;
    for (final b in [...breaths(vid(93, 1), vid(93, 11)), ...breaths(vid(94, 1), vid(94, 3))]) {
      last = s.hear(b);
    }
    expect(ref(last!.verseId), '94:3');
    expect(s.lock(), isNull);
  });
}
