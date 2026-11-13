import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/engine/matcher.dart';
import 'package:rafiq/core/engine/tracker.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/features/listen/listen_state.dart';

import '../support/fakes.dart';

/// `ListenState.place` (PLAN.md §38): the engine's tie report turned into one
/// of four places, conservatively.
void main() {
  /// A listening session with [track]; [lastSure] the position held, if any.
  ListenState listening(
    TrackState track, {
    Position? lastSure,
    Position? anchor,
    Hint? lock,
    TrackStatus? evidenceStatus,
    SessionPhase phase = SessionPhase.listening,
  }) =>
      ListenState(
        phase: phase,
        track: track,
        lastSure: lastSure,
        anchor: anchor,
        lock: lock,
        evidenceStatus: evidenceStatus ?? (track.evidence ? track.status : null),
      );

  List<int> surahsOf(Place place) => switch (place) {
        InSurah(:final surah) => [surah],
        AcrossSurahs(:final choices) => [for (final c in choices) c.surah],
        _ => const [],
      };

  group('the four places', () {
    test('nothing heard yet: Unplaced', () {
      expect(listening(TrackState.empty).place, const Unplaced());
      expect(const ListenState().place, const Unplaced());
    });

    test('a confirmed ayah: Placed', () {
      expect(listening(at(93, 3)).place, Placed(pos(93, 3)));
    });

    test('unsure with an ayah held: Placed on the held one, as before', () {
      final state = listening(at(2, 255, status: TrackStatus.uncertain), lastSure: pos(93, 3));
      expect(state.place, Placed(pos(93, 3)));
    });

    test('a trusted tie in one surah: InSurah, every copy', () {
      final place = listening(tie([(18, 89), (18, 92)])).place;
      expect(place, InSurah(18, [pos(18, 89), pos(18, 92)], null));
    });

    test('a trusted tie across two or three surahs: AcrossSurahs, grouped, in Quran order', () {
      final two = listening(tie([(54, 17), (54, 22), (73, 20)])).place as AcrossSurahs;
      expect(two.choices, [
        SurahChoice(54, [pos(54, 17), pos(54, 22)]),
        SurahChoice(73, [pos(73, 20)]),
      ]);
      expect(two.choices.first.only, isNull);
      expect(two.choices.last.only, pos(73, 20));

      final three = listening(tie([(3, 50), (26, 108), (26, 110), (43, 63)])).place;
      expect(surahsOf(three), [3, 26, 43]);
    });

    test('an untrusted tie is never a surah-level choice', () {
      expect(listening(tie([(18, 89), (18, 92)], trusted: false)).place, const Unplaced());
      final held = listening(tie([(77, 15), (83, 10)], trusted: false, position: pos(93, 3)), lastSure: pos(93, 3));
      expect(held.place, Placed(pos(93, 3)));
    });

    test('an incomplete report (one ayah, or trusted without a set) offers nothing', () {
      expect(listening(tie([(18, 89)])).place, const Unplaced());
      expect(listening(tie([])).place, const Unplaced());
    });

    test('more than three surahs: no list of choices', () {
      final four = tie([(3, 50), (26, 108), (43, 63), (71, 3)]);
      expect(listening(four).place, const Unplaced());
      expect(listening(four, lastSure: pos(93, 3)).place, Placed(pos(93, 3)));
    });
  });

  group('held positions, misses and confirmations', () {
    test('a far jump into repeated words keeps the held ayah: the surah is only a possibility', () {
      final state = listening(tie([(55, 13), (55, 16)], position: pos(93, 3)), lastSure: pos(93, 3));
      expect(state.place, InSurah(55, [pos(55, 13), pos(55, 16)], pos(93, 3)));
      expect(state.displayed, pos(93, 3), reason: 'the screen never jumps to a candidate');
    });

    test('during Al-Fatiha the held position is the imam\'s surah, not Al-Fatiha', () {
      final state = listening(
        tie([(3, 50), (43, 63)], position: pos(1, 7)),
        lastSure: pos(1, 7),
        anchor: pos(55, 13),
      );
      expect((state.place as AcrossSurahs).held, pos(55, 13));
    });

    test('a miss holds the tie, before and after a position (it invents nothing)', () {
      // Before any position the engine reports a miss as idle.
      final cold = tie([(18, 89), (18, 92)], evidence: false, status: TrackStatus.idle);
      expect(listening(cold, evidenceStatus: TrackStatus.uncertain).place, isA<InSurah>());
      final far = tie([(18, 89), (18, 92)], evidence: false, position: pos(93, 3));
      expect(
        listening(far, lastSure: pos(93, 3), evidenceStatus: TrackStatus.uncertain).place,
        InSurah(18, [pos(18, 89), pos(18, 92)], pos(93, 3)),
      );
    });

    test('lost: the tie is old news', () {
      final lost = tie([(18, 89), (18, 92)], evidence: false, position: pos(93, 3), status: TrackStatus.lost);
      expect(listening(lost, lastSure: pos(93, 3)).place, Placed(pos(93, 3)));
    });

    test('a confirmed position returns to Placed', () {
      expect(listening(at(18, 92), lastSure: pos(18, 92)).place, Placed(pos(18, 92)));
    });

    test('only while listening: not connecting, stopping, stopped, paused or failed', () {
      for (final phase in SessionPhase.values) {
        final place = listening(tie([(18, 89), (18, 92)]), phase: phase).place;
        expect(place is InSurah, phase == SessionPhase.listening, reason: phase.name);
      }
    });
  });

  group('Al-Fatiha and the basmala', () {
    test('a basmala is recited before every surah: never a choice', () {
      expect(listening(tie([(1, 1), (27, 30)])).place, const Unplaced());
      expect(listening(tie([(1, 1), (1, 3), (2, 163)])).place, const Unplaced());
    });

    test('one copy in Al-Fatiha is an ordinary choice', () {
      expect(surahsOf(listening(tie([(1, 2), (10, 10)])).place), [1, 10]);
    });

    test('copies within Al-Fatiha are not offered (it is never a surah to stay on)', () {
      expect(listening(tie([(1, 2), (1, 4), (10, 10)])).place, const Unplaced());
    });
  });

  group('locks', () {
    final across = tie([(3, 50), (26, 108), (26, 110), (43, 63)]);

    test('a surah lock narrows the tie at once to what the engine now searches', () {
      expect(listening(across, lock: const SurahHint(26)).place, InSurah(26, [pos(26, 108), pos(26, 110)], null));
      // The window is the surah and the next one.
      expect(listening(across, lock: const SurahHint(25)).place, isA<InSurah>());
      expect(listening(across, lock: const SurahHint(42)).place, const Unplaced(), reason: '43:63 alone');
    });

    test('a lock elsewhere leaves nothing to offer; one copy left is not a tie', () {
      expect(listening(across, lock: const SurahHint(55)).place, const Unplaced());
      expect(listening(across, lock: const SurahHint(3)).place, const Unplaced());
    });

    test('Al-Fatiha stays in any surah lock', () {
      expect(surahsOf(listening(tie([(1, 2), (10, 10)]), lock: const SurahHint(10)).place), [1, 10]);
    });

    test('a juz lock was applied by the engine: the tie is kept as reported', () {
      expect(surahsOf(listening(across, lock: const JuzHint(19)).place), [3, 26, 43]);
    });
  });

  group('the real tracker', () {
    late QuranMatcher matcher;
    setUpAll(() => matcher = QuranMatcher(indexOf(loadQuran())));

    Place cold(String text) => listening(fromEngine(Tracker(matcher).update(text))).place;

    test('the Ar-Rahman refrain: Ar-Rahman, all 31 copies', () {
      final place = cold('فبأي آلاء ربكما تكذبان') as InSurah;
      expect(place.surah, 55);
      expect(place.copies.length, 31);
      expect(place.held, isNull);
    });

    test('two copies in Al-Kahf: InSurah with both', () {
      expect(cold('ثم أتبع سببا'), InSurah(18, [pos(18, 89), pos(18, 92)], null));
    });

    test('a phrase in three surahs: one choice each, single copies directly', () {
      final place = cold('فاتقوا الله وأطيعون') as AcrossSurahs;
      expect([for (final c in place.choices) c.surah], [3, 26, 43]);
      expect(place.choices[0].only, pos(3, 50));
      expect(place.choices[1].copies.length, 8);
      expect(place.choices[2].only, pos(43, 63));
    });

    test('untrusted, incomplete, the basmala, Al-Fatiha\'s opening: nothing offered', () {
      for (final text in [
        'ويل يومئذ للمكذبين', // trusted false
        'يا أيها الذين آمنوا', // 89 copies, beyond the cap
        'بسم الله الرحمن الرحيم', // trusted, but the basmala
        'الرحمن الرحيم',
        'الحمد لله رب العالمين',
        'بلى مربي للقسط', // a garbled preview
      ]) {
        expect(cold(text), const Unplaced(), reason: text);
      }
    });

    test('a far jump holds Ad-Duha; a miss keeps the tie; the next distinct ayah places it', () {
      final tracker = Tracker(matcher);
      tracker.update('والضحى والليل إذا سجى');
      final held = fromEngine(tracker.update('ما ودعك ربك وما قلى')).position!;
      expect(held, pos(93, 3));

      final jump = listening(fromEngine(tracker.update('فبأي آلاء ربكما تكذبان')), lastSure: held);
      expect(jump.place, isA<InSurah>().having((p) => p.held, 'held', held));

      final miss = listening(fromEngine(tracker.update('zzz')), lastSure: held, evidenceStatus: TrackStatus.uncertain);
      expect(miss.place, isA<InSurah>().having((p) => p.surah, 'surah', 55));

      final next = fromEngine(tracker.update('يسأله من في السماوات والأرض كل يوم هو في شأن'));
      expect(next.tied, isEmpty);
      final placed = listening(next, lastSure: next.status == TrackStatus.tracking ? next.position : held);
      expect(placed.place, isA<Placed>());
    });

    test('inside a lock on Ash-Shu\'ara the phrase is Ash-Shu\'ara alone', () {
      final quran = loadQuran();
      final tracker = Tracker(matcher)..lock(quran.surah(26).firstVerseId, quran.surah(27).lastVerseId);
      final place = listening(fromEngine(tracker.update('فاتقوا الله وأطيعون')), lock: const SurahHint(26)).place;
      expect(place, isA<InSurah>().having((p) => p.surah, 'surah', 26));
    });
  });
}
