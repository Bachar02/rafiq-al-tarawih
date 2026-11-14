import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/data/khatm.dart';
import 'package:rafiq/data/note.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart' show loadQuran;

void main() {
  final nov1 = DateTime(2026, 11, 1);
  DateTime day(int n) => DateTime(2026, 11, n);

  /// A 30-day plan from page 1, Nov 1 to Nov 30.
  KhatmPlan plan({int startPage = 1, DateTime? endsOn}) =>
      KhatmPlan(startedOn: nov1, endsOn: endsOn ?? day(30), startPage: startPage);

  Iterable<int> range(int from, int to) => [for (var p = from; p <= to; p++) p];

  group('KhatmPlan', () {
    test('a fresh 30-day plan: 604 pages, 21 a day', () {
      final p = plan();
      expect(p.length, 30);
      expect(p.remaining, 604);
      expect(p.daysLeft(nov1), 30);
      expect(p.todayTarget(nov1), 21); // ceil(604 / 30)
      expect(p.nextPage, 1);
      expect(p.overdue(day(30)), isFalse);
      expect(p.overdue(DateTime(2026, 12, 1)), isTrue);
    });

    test('reading today does not shrink today\'s target', () {
      final p = plan().reading(nov1, range(1, 15));
      expect(p.readOn(nov1), 15);
      expect(p.todayTarget(nov1), 21);
      expect(p.nextPage, 16);
    });

    test('reading ahead lowers tomorrow\'s target; falling behind raises it', () {
      final ahead = plan().reading(nov1, range(1, 60));
      expect(ahead.todayTarget(day(2)), 19); // ceil(544 / 29)
      final behind = plan().reading(nov1, range(1, 5));
      expect(behind.todayTarget(day(2)), 21); // ceil(599 / 29)
      expect(plan().todayTarget(day(16)), 41, reason: 'nothing read in 15 days: ceil(604 / 15)');
    });

    test('overdue: everything left is today\'s target', () {
      final p = plan().reading(nov1, range(1, 500));
      final late = DateTime(2026, 12, 5);
      expect(p.overdue(late), isTrue);
      expect(p.daysLeft(late), 1);
      expect(p.todayTarget(late), 104);
    });

    test('a page read again keeps its first day and adds nothing', () {
      final p = plan().reading(nov1, [1, 2]);
      final again = p.reading(day(2), [2, 3]);
      expect(again.pages[2], '2026-11-01');
      expect(again.pages[3], '2026-11-02');
      expect(again.read, 3);
      expect(identical(p.reading(day(3), [1, 2]), p), isTrue, reason: 'nothing new: the same plan');
    });

    test('pages outside 1..604 are ignored', () {
      expect(plan().reading(nov1, [0, 605, -3]).read, 0);
    });

    test('the next page wraps around from the start page', () {
      var p = plan(startPage: 600);
      expect(p.nextPage, 600);
      p = p.reading(nov1, range(600, 604));
      expect(p.nextPage, 1, reason: 'after page 604, from the beginning');
      p = p.reading(nov1, range(1, 599));
      expect(p.complete, isTrue);
      expect(p.nextPage, isNull);
    });

    test('pages read but not counted yet move the next page on, not the plan', () {
      final p = plan().reading(nov1, range(1, 10));
      expect(p.nextPageCounting(range(11, 13)), 14);
      expect(p.nextPageCounting([300]), 11, reason: 'a page elsewhere fills no gap');
      expect(p.nextPage, 11);
      expect(p.read, 10);
    });

    test('a 365-day plan keeps every page, whatever the reading log forgets', () {
      var p = KhatmPlan(startedOn: DateTime(2026, 1, 1), endsOn: DateTime(2026, 12, 31), startPage: 1);
      expect(p.length, 365);
      for (var page = 1; page <= 604; page++) {
        p = p.reading(DateTime(2026, 1, 1).add(Duration(days: page * 364 ~/ 604)), [page]);
      }
      final back = KhatmPlan.fromJson(jsonDecode(jsonEncode(p.toJson())))!;
      expect(back.read, 604);
      expect(back.pages[1], '2026-01-01');
      expect(back.pages[604], '2026-12-31');
      expect(back, p);
    });

    test('days are calendar days across a clock change', () {
      // Europe and North America change the clock on the last Sunday of
      // October and the first Sunday of November.
      final p = KhatmPlan(startedOn: DateTime(2026, 10, 20), endsOn: DateTime(2026, 11, 10), startPage: 1);
      expect(p.length, 22);
      expect(p.daysLeft(DateTime(2026, 11, 10, 23, 30)), 1);
    });

    test('JSON keeps pages grouped by day and round-trips', () {
      final p = plan(startPage: 42).reading(nov1, [42, 43]).reading(day(2), [44]);
      final json = p.toJson();
      expect(json['pages'], {
        '2026-11-01': [42, 43],
        '2026-11-02': [44],
      });
      expect(KhatmPlan.fromJson(jsonDecode(jsonEncode(json))), p);
    });

    test('an unreadable plan is null; unreadable pages are dropped and reported', () {
      for (final bad in [
        {'v': 2, 'start': '2026-11-01', 'end': '2026-11-30', 'from': 1, 'pages': {}},
        {'v': 1, 'start': '2026-11-31', 'end': '2026-11-30', 'from': 1, 'pages': {}},
        {'v': 1, 'start': '2026-11-10', 'end': '2026-11-01', 'from': 1, 'pages': {}},
        {'v': 1, 'start': '2026-11-01', 'end': '2026-11-30', 'from': 605, 'pages': {}},
        {'v': 1, 'start': '2026-11-01', 'end': '2026-11-30', 'from': 1, 'pages': []},
      ]) {
        expect(KhatmPlan.fromJson(bad), isNull, reason: '$bad');
      }
      var dropped = false;
      final p = KhatmPlan.fromJson({
        'v': 1,
        'start': '2026-11-01',
        'end': '2026-11-30',
        'from': 1,
        'pages': {
          '2026-11-01': [1, 2, 900],
          'yesterday': [3],
        },
      }, onDropped: () => dropped = true)!;
      expect(p.pages.keys, [1, 2]);
      expect(dropped, isTrue);
    });
  });

  group('where to continue', () {
    final quran = loadQuran();
    final p = plan().reading(nov1, range(1, 10));
    int first(int page) => quran.pages.start(page);

    test('the khatm\'s next page, from its first ayah, wherever the reader is', () {
      expect(resumeVerse(quran, position: first(300), khatm: p), first(11));
      expect(resumeVerse(quran, position: first(5), khatm: p), first(11));
    });

    test('stopped in the middle of that page: that very ayah', () {
      final mid = first(11) + 2;
      expect(quran.pageOf(mid), 11);
      expect(resumeVerse(quran, position: mid, khatm: p), mid);
    });

    test('pages read but not counted yet: after them', () {
      final mid = first(13) + 1;
      expect(quran.pageOf(mid), 13);
      expect(resumeVerse(quran, position: mid, khatm: p, uncounted: range(11, 12)), mid);
      expect(resumeVerse(quran, position: first(400), khatm: p, uncounted: range(11, 12)), first(13));
    });

    test('no khatm, or every page read: the reader\'s place', () {
      expect(resumeVerse(quran, position: 1234), 1234);
      expect(resumeVerse(quran, position: 1234, khatm: p, uncounted: range(11, 604)), 1234);
    });
  });

  group('KhatmBook', () {
    test('round-trips, finished newest first', () {
      final book = KhatmBook(
        active: plan().reading(nov1, [1]),
        finished: [
          KhatmRecord(startedOn: DateTime(2026, 9, 1), completedOn: DateTime(2026, 9, 29)),
          KhatmRecord(startedOn: DateTime(2026, 10, 1), completedOn: DateTime(2026, 10, 30)),
        ],
      );
      final back = KhatmBook.fromJson(jsonDecode(jsonEncode(book.toJson())))!;
      expect(back.active, book.active);
      expect([for (final r in back.finished) r.completedOn.month], [10, 9]);
      expect(back.finished.last.days, 29);
    });

    test('no active plan round-trips', () {
      final back = KhatmBook.fromJson(jsonDecode(jsonEncode(KhatmBook.empty.toJson())))!;
      expect(back.active, isNull);
      expect(back.finished, isEmpty);
    });
  });

  group('Note', () {
    test('text is trimmed and kept to 2000 characters', () {
      expect(Note.clean('  سلام \n'), 'سلام');
      expect(Note.clean('   '), isEmpty);
      final long = 'ب' * 2500;
      expect(Note.clean(long).length, 2000);
      // Characters as the user sees them: an emoji is not cut in half.
      final emoji = '${'a' * 1999}👍🏽 tail';
      expect(Note.clean(emoji), '${'a' * 1999}👍🏽');
    });

    test('JSON round-trip, and what is unreadable', () {
      final n = Note(
        verseId: 262,
        text: 'Ayat al-Kursi',
        createdAt: DateTime.utc(2026, 11, 1).toLocal(),
        updatedAt: DateTime.utc(2026, 11, 2).toLocal(),
      );
      expect(Note.fromJson(jsonDecode(jsonEncode(n.toJson()))), n);
      for (final bad in [
        {'verse': 0, 'text': 'x', 'at': '2026-11-01T00:00:00Z', 'edited': '2026-11-01T00:00:00Z'},
        {'verse': 1, 'text': '  ', 'at': '2026-11-01T00:00:00Z', 'edited': '2026-11-01T00:00:00Z'},
        {'verse': 1, 'text': 'x', 'at': 'soon', 'edited': '2026-11-01T00:00:00Z'},
        [1, 2],
      ]) {
        expect(Note.fromJson(bad), isNull, reason: '$bad');
      }
    });
  });

  group('the store', () {
    Future<(PrefsReadingStore, SharedPreferences)> store([Map<String, Object> values = const {}]) async {
      SharedPreferences.setMockInitialValues(values);
      final prefs = await SharedPreferences.getInstance();
      return (PrefsReadingStore(prefs), prefs);
    }

    List<String?> keptAside(SharedPreferences prefs) =>
        [for (final k in prefs.getKeys().where((k) => k.contains('.unreadable.'))) prefs.getString(k)];

    test('nothing saved: no plan, no notes', () async {
      final (s, _) = await store();
      expect(s.khatm().active, isNull);
      expect(s.khatm().finished, isEmpty);
      expect(s.notes(), isEmpty);
    });

    test('the khatm book survives a restart', () async {
      final (s, prefs) = await store();
      final book = KhatmBook(active: plan().reading(nov1, [1, 2, 3]));
      expect(await s.saveKhatm(book), isTrue);
      expect(PrefsReadingStore(prefs).khatm(), book);
    });

    test('an unreadable khatm record is kept aside before the next save', () async {
      for (final raw in ['{oops', '{"v":2,"active":null,"finished":[]}', '{"v":1,"active":{"v":1},"finished":[]}']) {
        final (s, prefs) = await store({PrefsReadingStore.khatmKey: raw});
        expect(s.khatm().active, isNull, reason: raw);
        expect(await s.saveKhatm(KhatmBook(active: plan())), isTrue);
        expect(keptAside(prefs), [raw], reason: raw);
        expect(s.khatm().active, plan());
      }
    });

    test('a khatm record with a damaged page keeps the rest, and the original', () async {
      const raw = '{"v":1,"active":{"v":1,"start":"2026-11-01","end":"2026-11-30","from":1,'
          '"pages":{"2026-11-01":[1,2,"3"]}},"finished":[{"start":"x","done":"y"}]}';
      final (s, prefs) = await store({PrefsReadingStore.khatmKey: raw});
      final book = s.khatm();
      expect(book.active!.pages.keys, [1, 2]);
      expect(book.finished, isEmpty);
      await s.saveKhatm(book);
      expect(keptAside(prefs), [raw]);
    });

    test('notes round-trip newest edit first', () async {
      final (s, prefs) = await store();
      Note note(int verse, int edited) =>
          Note(verseId: verse, text: 'n$verse', createdAt: day(1), updatedAt: day(edited));
      await s.saveNotes([note(10, 2), note(20, 5), note(30, 3)]);
      expect([for (final n in PrefsReadingStore(prefs).notes()) n.verseId], [20, 30, 10]);
    });

    test('readable notes survive a damaged one; two on one ayah keep the newer', () async {
      const raw = '{"v":1,"items":['
          '{"verse":10,"text":"old","at":"2026-11-01T00:00:00Z","edited":"2026-11-01T00:00:00Z"},'
          '{"verse":10,"text":"new","at":"2026-11-01T00:00:00Z","edited":"2026-11-03T00:00:00Z"},'
          '{"verse":99999,"text":"x","at":"2026-11-01T00:00:00Z","edited":"2026-11-01T00:00:00Z"},'
          '{"verse":20,"text":"kept","at":"2026-11-01T00:00:00Z","edited":"2026-11-02T00:00:00Z"}]}';
      final (s, prefs) = await store({PrefsReadingStore.notesKey: raw});
      expect([for (final n in s.notes()) n.text], ['new', 'kept']);
      await s.saveNotes(s.notes());
      expect(keptAside(prefs), [raw]);
    });

    test('a notes record of the wrong shape is kept and reads as empty', () async {
      final (s, prefs) = await store({PrefsReadingStore.notesKey: '{"v":1,"items":{}}'});
      expect(s.notes(), isEmpty);
      await s.saveNotes(const []);
      expect(keptAside(prefs), ['{"v":1,"items":{}}']);
    });
  });
}
