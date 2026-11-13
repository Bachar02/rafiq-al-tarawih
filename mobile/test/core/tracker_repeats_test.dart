import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/engine/matcher.dart';
import 'package:rafiq/core/engine/quran_index.dart';
import 'package:rafiq/core/engine/tracker.dart';
import 'package:rafiq/data/quran.dart';

import '../support/fakes.dart';

/// Repeated text (PLAN.md §35): an unconfirmed position (cold start, far jump)
/// is decided by its own text. Another ayah scoring within `tieMargin` of the
/// best is a rival, however close; and confirming needs real confidence. The
/// same cases as engine/tests/test_tracking.py; tracker.json checks every
/// state against Python as well.
void main() {
  late Quran quran;
  late QuranIndex index;
  late QuranMatcher matcher;
  late Tracker tracker;
  int vid(int surah, int ayah) => quran.surah(surah).firstVerseId + ayah - 1;
  int surahOf(int verseId) => quran.verse(verseId).surah;
  List<TrackerState> feed(List<String> chunks) => [for (final c in chunks) tracker.update(c)];
  String words(int verseId) {
    final (a, b) = index.verseSpan(verseId);
    return index.words.sublist(a, b).join(' ');
  }

  const refrain = 'فبأي آلاء ربكما تكذبان'; // 31 times in Ar-Rahman, 55:13 to 55:77
  const duha = ['والضحى والليل إذا سجى', 'ما ودعك ربك وما قلى'];
  const after = ['يسأله من في السماوات والأرض كل يوم هو في شأن', 'سنفرغ لكم أيها الثقلان']; // 55:29, 55:31

  setUpAll(() {
    quran = loadQuran();
    index = QuranIndex([for (final v in quran.verses) v.text]);
    matcher = QuranMatcher(index);
  });
  setUp(() => tracker = Tracker(matcher));

  test('an exact tie close by is not shown at cold start', () {
    final tie = tracker.update('ثم أتبع سببا'); // 18:89 and 18:92
    expect(tie.verseId, isNull);
    expect(tie.confidence, 0);
    expect(tie.pendingVerse, vid(18, 89));
    expect(tie.alternatives, contains(vid(18, 92)));
    expect(tracker.update('حتى إذا بلغ بين السدين وجد من دونهما قوما').verseId, vid(18, 93));
  });

  test('a misheard word between two copies is a tie', () {
    final tie = tracker.update('وإن مع العسر يسرا'); // 94:5 begins فإن, 94:6 إن
    expect(tie.verseId, isNull);
    expect({tie.pendingVerse, ...tie.alternatives}, containsAll([vid(94, 5), vid(94, 6)]));
  });

  test('a near tie is a tie: exact ties alone would show the first copy', () {
    const chunks = [refrain, 'فيهما عينان تجريان فبأي آلاء']; // 55:49, then 55:50 and the start of 55:51
    final exactOnly = Tracker(matcher, config: const TrackerConfig(tieMargin: 0));
    expect([for (final c in chunks) exactOnly.update(c).verseId].last, vid(55, 18));
    expect(feed(chunks).every((s) => s.verseId == null), isTrue);
    expect(tracker.update('فيهما من كل فاكهة زوجان').verseId, vid(55, 52));
  });

  test('the Ar-Rahman refrain names the surah and waits', () {
    for (var i = 0; i < 2; i++) {
      final state = tracker.update(refrain); // two copies confirm nothing
      expect(state.verseId, isNull);
      expect(state.confidence, 0);
      expect({
        for (final v in [state.pendingVerse!, ...state.alternatives]) surahOf(v)
      }, {
        55
      });
    }
    expect(tracker.update(after[0]).verseId, vid(55, 29));
  });

  test('joining on a later copy shows the right place once it is distinct', () {
    expect(tracker.update(refrain).verseId, isNull);
    expect(tracker.update('ولمن خاف مقام ربه جنتان').verseId, vid(55, 46));
  });

  test('repeated verses are never shown at cold start', () {
    final byText = <String, int>{};
    for (final v in quran.verses) {
      byText.update(words(v.id), (n) => n + 1, ifAbsent: () => 1);
    }
    final repeated = [
      for (final e in byText.entries)
        if (e.value >= 2 && e.key.split(' ').length >= 3) e.key
    ];
    expect(repeated.length, greaterThan(80));
    expect([
      for (final t in repeated)
        if (Tracker(matcher).update(t).verseId != null) t
    ], isEmpty);
  });

  test('unique text is unchanged at cold start', () {
    const off = TrackerConfig(tieMargin: -1);
    var checked = 0;
    for (var v = 1; v <= quran.verses.length; v += 10) {
      final text = words(v);
      final exact = matcher.matchTokens(text.split(' '), k: 3).where((m) => m.score >= 0.999).length;
      if (exact > 1) continue; // fits exactly elsewhere too (102:3 is the end of 102:4)
      final now = Tracker(matcher).update(text), before = Tracker(matcher, config: off).update(text);
      expect((now.verseId, now.status, now.confidence), (before.verseId, before.status, before.confidence),
          reason: '$v');
      checked++;
    }
    expect(checked, greaterThan(550));
  });

  test('a far jump into repeated text waits for distinct words', () {
    feed(duha);
    for (final held in feed([refrain, refrain])) {
      expect(held.verseId, vid(93, 3), reason: 'never a copy of the refrain');
      expect(held.status, TrackerStatus.uncertain);
    }
    expect(feed(after).last.verseId, vid(55, 31));
  });

  test('after lost and al-Fatiha, repeated text still waits', () {
    feed([...duha, ...List.filled(tracker.config.lostAfter, 'zzz')]);
    feed(['الحمد لله رب العالمين', 'الرحمن الرحيم مالك يوم الدين']);
    for (final held in feed([refrain, refrain])) {
      expect(held.verseId == null || surahOf(held.verseId!) != 55, isTrue);
    }
  });

  test('a far jump on distinct words still confirms in two', () {
    feed(duha);
    final first = tracker.update('الله لا إله إلا هو الحي القيوم');
    expect(first.verseId, vid(93, 3));
    expect(first.pendingVerse, vid(2, 255));
    expect(tracker.update('لا تأخذه سنة ولا نوم').verseId, vid(2, 255));
  });
}
