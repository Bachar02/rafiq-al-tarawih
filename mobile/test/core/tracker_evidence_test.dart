import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/engine/matcher.dart';
import 'package:rafiq/core/engine/quran_index.dart';
import 'package:rafiq/core/engine/tracker.dart';

import '../support/fakes.dart';

/// `TrackerState.evidence`: a miss (audio that matched no Quran) is no news,
/// not doubt. The same cases as engine/tests/test_tracking.py; the golden
/// files check every state against Python as well.
void main() {
  late QuranMatcher matcher;
  late Tracker tracker;
  int vid(int surah, int ayah) => loadQuran().surah(surah).firstVerseId + ayah - 1;
  List<TrackerState> feed(List<String> chunks) => [for (final c in chunks) tracker.update(c)];

  setUpAll(() => matcher = QuranMatcher(QuranIndex([for (final v in loadQuran().verses) v.text])));
  setUp(() => tracker = Tracker(matcher));

  test('a miss carries no evidence and holds the position', () {
    var following = feed(['والضحى والليل إذا سجى', 'ما ودعك ربك وما قلى']).last;
    expect(following.status, TrackerStatus.tracking);
    expect(following.evidence, isTrue);
    for (final chunk in ['zzz', '', 'الم']) {
      final miss = tracker.update(chunk);
      expect(miss.evidence, isFalse, reason: chunk);
      expect(miss.status, TrackerStatus.uncertain);
      expect(miss.confidence, 0);
      expect(
          (miss.verseId, miss.word, miss.upcomingVerse), (following.verseId, following.word, following.upcomingVerse));
      expect(miss.pendingVerse, following.pendingVerse);
      expect(miss.alternatives, following.alternatives);
      following = tracker.update('وللآخرة خير لك من الأولى');
      expect(following.evidence, isTrue);
    }
  });

  test('misses in a row are lost, without evidence', () {
    feed(['والضحى والليل إذا سجى', 'ما ودعك ربك وما قلى']);
    final n = tracker.config.lostAfter;
    final states = feed(List.filled(n, 'zzz'));
    expect([for (final s in states) s.status], [...List.filled(n - 1, TrackerStatus.uncertain), TrackerStatus.lost]);
    expect(states.any((s) => s.evidence), isFalse);
  });

  test('a previewed miss says so and changes nothing', () {
    feed(['والضحى والليل إذا سجى']);
    final before = tracker.state;
    final preview = tracker.preview('zzz');
    expect(preview.evidence, isFalse);
    expect(identical(tracker.state, before), isTrue);
    expect(tracker.preview('ما ودعك ربك وما قلى').evidence, isTrue);
  });

  test('idle and cold-start misses have no evidence', () {
    expect(tracker.state.evidence, isFalse);
    expect(tracker.update('zzz').evidence, isFalse);
    expect(tracker.state.status, TrackerStatus.idle);
  });

  test('an exact tie is evidence with confidence 0', () {
    // The same words five times in Ash-Shu'ara.
    final tie = tracker.update('فاتقوا الله وأطيعون وما أسألكم عليه من أجر');
    expect(tie.evidence, isTrue);
    expect(tie.confidence, 0);
    expect(tie.status, TrackerStatus.uncertain);
    expect(tie.alternatives.length, greaterThanOrEqualTo(2));
  });

  test('competing hypotheses are evidence of doubt; a miss keeps them', () {
    feed(['والضحى والليل إذا سجى', 'ما ودعك ربك وما قلى']);
    final far = tracker.update('الله لا إله إلا هو الحي القيوم'); // Ayat al-Kursi, unconfirmed
    expect(far.evidence, isTrue);
    expect(far.status, TrackerStatus.uncertain);
    expect(far.pendingVerse, vid(2, 255));
    final held = tracker.update('zzz');
    expect(held.evidence, isFalse);
    expect(held.pendingVerse, vid(2, 255));
  });

  test("the user's position is evidence", () {
    expect(tracker.setPosition(vid(36, 1)).evidence, isTrue);
  });
}
