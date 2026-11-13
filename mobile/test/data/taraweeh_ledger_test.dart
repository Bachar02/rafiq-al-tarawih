import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/data/quran.dart';
import 'package:rafiq/data/taraweeh_ledger.dart';

import '../support/fakes.dart';

/// The Taraweeh ledger's rules (PLAN.md §39), on SIMULATED nights: sequences
/// of committed ayahs as the listening session would report them, with
/// times. No audio and no recognition here; `taraweeh_replay_test.dart`
/// replays real recorded recognition through the same path.
void main() {
  final quran = loadQuran();
  int v(int surah, int ayah) => quran.verseId(surah, ayah)!;

  /// A night: Isha at 20:00 is the same night as Taraweeh at 21:30 and qiyam
  /// at 02:00.
  final night1 = DateTime(2027, 2, 9, 21, 30);

  /// Recite [surah] ayahs [from]..[to], one every [every], starting [at].
  /// Returns the time after the last.
  ({TaraweehLedger ledger, DateTime at}) recite(
    TaraweehLedger ledger,
    DateTime at,
    int surah,
    int from,
    int to, {
    Duration every = const Duration(seconds: 20),
    int step = 1,
  }) {
    for (var a = from; a <= to; a += step) {
      ledger = ledger.observe(v(surah, a), at);
      at = at.add(every);
    }
    return (ledger: ledger, at: at);
  }

  /// Al-Fatiha at a rakʿah, as committed results.
  TaraweehLedger fatiha(TaraweehLedger ledger, DateTime at) {
    for (var a = 1; a <= 7; a++) {
      ledger = ledger.observe(v(1, a), at);
    }
    return ledger;
  }

  int? end(TaraweehLedger ledger) => ledger.progress(quran)?.verseId;

  group('one night', () {
    test('consecutive recitation: the stopping point is the last ayah heard', () {
      final r = recite(TaraweehLedger.empty, night1, 2, 142, 176);
      expect(end(r.ledger), v(2, 176));
      expect(r.ledger.progress(quran)!.ayahs, 35);
    });

    test('several surahs in one night, across their boundaries', () {
      var r = recite(TaraweehLedger.empty, night1, 77, 1, 50);
      r = recite(r.ledger, r.at, 78, 1, 40);
      r = recite(r.ledger, r.at, 79, 1, 10);
      expect(end(r.ledger), v(79, 10));
    });

    test('Al-Fatiha at every rakʿah is never progress, and never breaks the passage', () {
      var ledger = TaraweehLedger.empty;
      var at = night1;
      for (var rakah = 0; rakah < 8; rakah++) {
        ledger = fatiha(ledger, at);
        final r = recite(ledger, at.add(const Duration(minutes: 1)), 3, 1 + rakah * 10, 10 + rakah * 10);
        ledger = r.ledger;
        at = r.at.add(const Duration(minutes: 3)); // rukuʿ, sujud, salam
      }
      ledger = fatiha(ledger, at); // the last rakʿah's Al-Fatiha, after the passage
      expect(end(ledger), v(3, 80));
      expect(ledger.nights.single.runs.any((r) => r.first <= 7), isFalse);
    });

    test('repeated ayahs (the imam repeats, recognition reports one twice) change nothing', () {
      var ledger = TaraweehLedger.empty;
      var at = night1;
      for (final a in [1, 2, 2, 3, 2, 3, 4, 4, 5, 6, 5, 6, 7]) {
        ledger = ledger.observe(v(55, a), at);
        at = at.add(const Duration(seconds: 10));
      }
      expect(end(ledger), v(55, 7));
      expect(ledger.nights.single.runs, hasLength(1));
      expect(ledger.nights.single.runs.single.ayahs, 7);
    });

    test('a short ayah never reported (inside one chunk) does not split the passage', () {
      final r = recite(TaraweehLedger.empty, night1, 26, 1, 40, step: 3);
      expect(r.ledger.nights.single.runs, hasLength(1));
      // Each skip counts once the imam is heard after it: the last one waits.
      expect(end(r.ledger), v(26, 37));
      expect(end(r.ledger.observe(v(26, 41), r.at)), v(26, 41));
    });

    test('a garbled chunk matching a few ayahs on, then the imam behind it: a blip, dropped', () {
      // As on Husary's recording of 22:30–33 (real, taraweeh_replay_test).
      var ledger = TaraweehLedger.empty;
      var at = night1;
      for (final a in [30, 30, 31, 31, 34, 32, 32, 33, 33]) {
        ledger = ledger.observe(v(22, a), at);
        at = at.add(const Duration(seconds: 6));
      }
      expect(end(ledger), v(22, 33));
      expect(ledger.nights.single.runs.single.ahead, isNull);
    });

    test('a pending skip survives saving', () {
      final ledger = TaraweehLedger.empty.observe(v(22, 30), night1).observe(v(22, 33), night1);
      final again = TaraweehLedger.fromJson(ledger.toJson())!;
      expect(again.nights.single.runs.single.ahead, v(22, 33));
      expect(
          TaraweehLedger.fromJson({
            'v': 1,
            'nights': [
              {
                'night': '2027-02-09',
                'runs': [
                  {
                    'first': 10,
                    'last': 12,
                    'ayahs': 3,
                    'from': '2027-02-09T20:00:00Z',
                    'to': '2027-02-09T20:01:00Z',
                    'ahead': 13
                  },
                ],
              },
            ],
          })!
              .nights
              .single
              .runs,
          isEmpty,
          reason: 'a skip of one is not a skip: unreadable');
    });

    test('recognition lost the imam for a while: the two parts are one passage', () {
      var r = recite(TaraweehLedger.empty, night1, 4, 1, 20);
      r = recite(r.ledger, r.at.add(const Duration(minutes: 4)), 4, 45, 70); // 24 ayahs never heard
      expect(r.ledger.nights.single.runs, hasLength(2));
      expect(end(r.ledger), v(4, 70));
    });

    test('long pauses (rukuʿ, sujud, a break after four rakʿahs) are not an end', () {
      var r = recite(TaraweehLedger.empty, night1, 18, 1, 30);
      r = recite(r.ledger, r.at.add(const Duration(minutes: 25)), 18, 31, 60);
      expect(end(r.ledger), v(18, 60));
    });
  });

  group('what is not Taraweeh', () {
    test('Witr after Taraweeh (Al-Aʿla, Al-Kafirun, Al-Ikhlas) is not where it stopped', () {
      var r = recite(TaraweehLedger.empty, night1, 2, 203, 252);
      r = recite(r.ledger, r.at.add(const Duration(minutes: 3)), 87, 1, 19);
      r = recite(r.ledger, r.at.add(const Duration(minutes: 2)), 109, 1, 6);
      r = recite(r.ledger, r.at.add(const Duration(minutes: 2)), 112, 1, 4);
      expect(end(r.ledger), v(2, 252));
    });

    test('Witr in juz 30, after a passage in juz 30, skipping a surah: not linked', () {
      var r = recite(TaraweehLedger.empty, night1, 84, 1, 25);
      r = recite(r.ledger, r.at, 85, 1, 22);
      r = recite(r.ledger, r.at.add(const Duration(minutes: 3)), 87, 1, 19); // 86 skipped: Witr
      expect(end(r.ledger), v(85, 22));
    });

    test('qunut quoting ayahs (2:201, 3:8) is not where it stopped', () {
      final r = recite(TaraweehLedger.empty, night1, 2, 142, 176);
      var ledger = r.ledger.observe(v(2, 201), r.at.add(const Duration(minutes: 5)));
      ledger = ledger.observe(v(3, 8), r.at.add(const Duration(minutes: 6)));
      ledger = ledger.observe(v(2, 286), r.at.add(const Duration(minutes: 7)));
      expect(end(ledger), v(2, 176));
    });

    test('a quotation close after the passage end does not extend it', () {
      final r = recite(TaraweehLedger.empty, night1, 2, 142, 176);
      final ledger = r.ledger.observe(v(2, 186), r.at.add(const Duration(minutes: 5))); // a dua ayah, 10 on
      expect(end(ledger), v(2, 176));
    });

    test('a khatera quoting ayahs here and there, before Taraweeh', () {
      var ledger = TaraweehLedger.empty;
      var at = night1.subtract(const Duration(minutes: 20));
      for (final (s, a) in [(2, 183), (2, 185), (97, 1), (97, 2), (3, 133), (39, 53)]) {
        ledger = ledger.observe(v(s, a), at);
        at = at.add(const Duration(minutes: 1));
      }
      final r = recite(ledger, night1, 5, 1, 30);
      expect(end(r.ledger), v(5, 30));
    });

    test('Isha before Taraweeh (a few ayahs elsewhere) is not where it stopped', () {
      var r = recite(TaraweehLedger.empty, night1.subtract(const Duration(hours: 1, minutes: 30)), 59, 18, 24);
      r = recite(r.ledger, night1, 6, 1, 45);
      expect(end(r.ledger), v(6, 45));
      expect(r.ledger.nights, hasLength(1), reason: 'Isha and Taraweeh are one night');
    });

    test('qiyam after midnight belongs to the same night', () {
      var r = recite(TaraweehLedger.empty, night1, 10, 1, 30);
      r = recite(r.ledger, DateTime(2027, 2, 10, 2, 30), 10, 31, 60);
      expect(r.ledger.nights, hasLength(1));
      expect(end(r.ledger), v(10, 60));
    });
  });

  group('weak or contradictory evidence keeps the progress before', () {
    final lastNight = recite(TaraweehLedger.empty, night1, 2, 142, 176).ledger;
    final tonight = night1.add(const Duration(days: 1));

    test('a night of a couple of ayahs (the app opened late, the mic covered)', () {
      final ledger = lastNight.observe(v(2, 177), tonight).observe(v(2, 178), tonight);
      expect(end(ledger), v(2, 176));
      expect(TaraweehLedger.judge(ledger.nights.last, v(2, 176), quran).reason, VerdictReason.weak);
    });

    test('two passages of about the same length, neither continuing: unknown, kept', () {
      var r = recite(lastNight, tonight, 20, 1, 6);
      r = recite(r.ledger, r.at.add(const Duration(minutes: 5)), 36, 1, 7);
      expect(end(r.ledger), v(2, 176));
      expect(TaraweehLedger.judge(r.ledger.nights.last, v(2, 176), quran).reason, VerdictReason.contradictory);
    });

    test('...but the one continuing last night is Taraweeh', () {
      var r = recite(lastNight, tonight, 2, 177, 182);
      r = recite(r.ledger, r.at.add(const Duration(minutes: 5)), 36, 1, 7);
      expect(end(r.ledger), v(2, 182));
    });

    test('a longer passage elsewhere wins over a short continuation', () {
      var r = recite(lastNight, tonight, 2, 177, 180);
      r = recite(r.ledger, r.at.add(const Duration(minutes: 5)), 7, 1, 60);
      expect(end(r.ledger), v(7, 60));
    });
  });

  group('across nights', () {
    test('the next night continues; each night keeps its own record', () {
      var r = recite(TaraweehLedger.empty, night1, 2, 142, 176);
      r = recite(r.ledger, night1.add(const Duration(days: 1)), 2, 177, 210);
      expect(r.ledger.nights.map((n) => n.key), ['2027-02-09', '2027-02-10']);
      expect(end(r.ledger), v(2, 210));
      expect(r.ledger.progress(quran)!.night, '2027-02-10');
    });

    test('nights skipped: tonight starts far ahead and is still recognised', () {
      var r = recite(TaraweehLedger.empty, night1, 2, 142, 176);
      r = recite(r.ledger, night1.add(const Duration(days: 4)), 3, 92, 140);
      expect(end(r.ledger), v(3, 140));
    });

    test('a night without Taraweeh heard leaves the last one in place', () {
      final ledger = recite(TaraweehLedger.empty, night1, 2, 142, 176).ledger;
      final quiet = ledger.observe(v(112, 1), night1.add(const Duration(days: 1)));
      expect(end(quiet), v(2, 176));
      expect(quiet.progress(quran)!.night, '2027-02-09');
    });

    test('history is capped at two Ramadans', () {
      var ledger = TaraweehLedger.empty;
      for (var d = 0; d < TaraweehLedger.maxNights + 5; d++) {
        ledger = recite(ledger, night1.add(Duration(days: d)), 2, 10, 13).ledger;
      }
      expect(ledger.nights, hasLength(TaraweehLedger.maxNights));
    });

    test('a night with many quotations forgets single ayahs first', () {
      var ledger = recite(TaraweehLedger.empty, night1, 2, 142, 176).ledger;
      for (var i = 0; i < TaraweehLedger.maxRuns + 10; i++) {
        ledger = ledger.observe(1000 + i * 10, night1.add(Duration(minutes: 30 + i)));
      }
      expect(ledger.nights.single.runs.length, TaraweehLedger.maxRuns);
      expect(end(ledger), v(2, 176));
    });
  });

  group('the user corrects it afterwards', () {
    test('a correction overrides the night, and later nights continue from it', () {
      var r = recite(TaraweehLedger.empty, night1, 2, 142, 176);
      final fixed = r.ledger.correct(v(2, 180), DateTime(2027, 2, 10, 9));
      expect(fixed.nights, hasLength(1), reason: 'the next morning corrects last night');
      expect(end(fixed), v(2, 180));
      expect(fixed.progress(quran)!.fixedBy, FixSource.user);
      r = recite(fixed, night1.add(const Duration(days: 1)), 2, 181, 200);
      expect(end(r.ledger), v(2, 200));
    });

    test('an inferred-wrong night: the correction recovers the right continuation', () {
      // The imam recited 2:142–176, but recognition only caught Witr well.
      var r = recite(TaraweehLedger.empty, night1, 87, 1, 19);
      expect(end(r.ledger), v(87, 19));
      final fixed = r.ledger.correct(v(2, 176), DateTime(2027, 2, 10, 9));
      // The next night continues from the corrected point, beating Witr again.
      r = recite(fixed, night1.add(const Duration(days: 1)), 2, 177, 186);
      r = recite(r.ledger, r.at, 87, 1, 19);
      expect(end(r.ledger), v(2, 186));
    });

    test('with nothing recorded, a correction is that night', () {
      final ledger = TaraweehLedger.empty.correct(v(5, 81), DateTime(2027, 2, 10, 9));
      expect(ledger.nights.single.key, '2027-02-09');
      expect(end(ledger), v(5, 81));
    });

    test('the single position of earlier versions is carried over as set by hand', () {
      final ledger = TaraweehLedger.fromLegacy(v(5, 81), DateTime(2026, 11, 3, 22));
      expect(ledger.progress(quran)!.fixedBy, FixSource.legacy);
      final r = recite(ledger, DateTime(2026, 11, 4, 21), 5, 82, 100);
      expect(end(r.ledger), v(5, 100));
    });
  });

  test('night keys: the evening and the small hours are one night', () {
    expect(TaraweehLedger.nightOf(DateTime(2027, 2, 9, 19, 45)), '2027-02-09');
    expect(TaraweehLedger.nightOf(DateTime(2027, 2, 10, 3, 10)), '2027-02-09');
    expect(TaraweehLedger.nightOf(DateTime(2027, 2, 10, 12, 1)), '2027-02-10');
  });

  test('every ayah id outside the Quran is ignored', () {
    expect(TaraweehLedger.empty.observe(0, night1).nights, isEmpty);
    expect(TaraweehLedger.empty.observe(Quran.verseCount + 1, night1).nights, isEmpty);
    expect(TaraweehLedger.empty.correct(-3, night1).nights, isEmpty);
  });
}
