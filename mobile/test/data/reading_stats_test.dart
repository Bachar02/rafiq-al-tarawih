import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/data/reading_stats.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/progress/reading_grid.dart';
import 'package:rafiq/features/progress/reminder.dart';

ReadingLog log(Map<String, List<int>> days) => ReadingLog({for (final e in days.entries) e.key: e.value.toSet()});

List<int> pages(int from, int count) => [for (var p = from; p < from + count; p++) p];

void main() {
  test('shades: none, 1–4, 5–9, 10–19, a juz or more', () {
    expect([
      for (final p in [0, 1, 4, 5, 9, 10, 19, 20, 604]) readingLevel(p)
    ], [
      0,
      1,
      1,
      2,
      2,
      3,
      3,
      4,
      4
    ]);
  });

  group('a day\'s pages', () {
    test('count those counted and those waiting for review, each page once', () {
      final s = ReadingStats(
        log({
          '2026-11-03': [1, 2, 3]
        }),
        log({
          '2026-11-03': [3, 4],
          '2026-11-04': [5]
        }),
        DateTime(2026, 11, 4, 9),
      );
      expect(s.pagesOn(DateTime(2026, 11, 3)), 4);
      expect(s.pagesOn(DateTime(2026, 11, 4, 23, 59)), 1);
      expect(s.readToday, isTrue);
      expect(s.pagesOn(DateTime(2026, 11, 2)), 0);
    });
  });

  group('the run of days', () {
    final history = log({
      '2026-10-25': [1],
      '2026-10-26': [2],
      '2026-10-27': [3],
      '2026-10-28': [4],
      // a day without reading
      '2026-10-30': [5],
      '2026-10-31': [6],
      '2026-11-01': [7],
    });

    test('counts up to today, and today unread does not end it yet', () {
      final s = ReadingStats(history, const ReadingLog(), DateTime(2026, 11, 2, 21));
      expect(s.readToday, isFalse);
      expect(s.currentRun, 3);
      expect(s.bestRun, 4);
    });

    test('a page today adds today', () {
      final s = ReadingStats(
          history,
          log({
            '2026-11-02': [8]
          }),
          DateTime(2026, 11, 2, 21));
      expect(s.currentRun, 4);
    });

    test('a whole day missed starts over, without erasing the best', () {
      final s = ReadingStats(history, const ReadingLog(), DateTime(2026, 11, 3, 8));
      expect(s.currentRun, 0);
      expect(s.bestRun, 4);
    });

    test('runs cross month and year ends', () {
      final s = ReadingStats(
        log({
          '2026-12-30': [1],
          '2026-12-31': [2],
          '2027-01-01': [3]
        }),
        const ReadingLog(),
        DateTime(2027, 1, 1, 12),
      );
      expect(s.currentRun, 3);
      expect(s.bestRun, 3);
      expect(s.daysThisYear, 1, reason: 'a new year starts at zero');
    });

    test('nothing read: no run at all', () {
      final s = ReadingStats(const ReadingLog(), const ReadingLog(), DateTime(2026, 11, 4));
      expect(s.currentRun, 0);
      expect(s.bestRun, 0);
      expect(s.daysThisYear, 0);
      expect(s.pagesThisMonth, 0);
    });
  });

  test('totals: days read this year, pages this month', () {
    final s = ReadingStats(
      log({
        '2025-12-31': pages(1, 20),
        '2026-10-31': pages(1, 5),
        '2026-11-01': pages(6, 3),
        '2026-11-04': pages(9, 2)
      }),
      const ReadingLog(),
      DateTime(2026, 11, 4),
    );
    expect(s.daysThisYear, 3);
    expect(s.pagesThisMonth, 5);
    expect(s.daysSince(DateTime(2026, 11, 1)), 2);
  });

  group('the grid\'s weeks', () {
    final wednesday = DateTime(2026, 11, 4);

    test('start on the locale\'s first day of the week', () {
      expect(weekStart(wednesday, 0), DateTime(2026, 11, 1), reason: 'Sunday');
      expect(weekStart(wednesday, 1), DateTime(2026, 11, 2), reason: 'Monday');
      expect(weekStart(wednesday, 6), DateTime(2026, 10, 31), reason: 'Saturday');
      expect(weekStart(DateTime(2026, 11, 1), 0), DateTime(2026, 11, 1), reason: 'already the first day');
    });

    test('end with today\'s week', () {
      expect(gridStart(wednesday, 1, 0), DateTime(2026, 11, 1));
      expect(gridStart(wednesday, 3, 1), DateTime(2026, 10, 19));
      expect(gridStart(wednesday, 53, 1), DateTime(2025, 11, 3));
    });
  });

  group('when the reminders fire', () {
    List<DateTime> times(DateTime now, {bool read = false, int minutes = 20 * 60}) =>
        reminderTimes(now: now, minutes: minutes, readToday: read);

    test('today, if not read yet and the time is ahead; then each day for a week', () {
      final t = times(DateTime(2026, 11, 4, 19));
      expect(t.first, DateTime(2026, 11, 4, 20));
      expect(t, hasLength(reminderDays));
      expect(t.last, DateTime(2026, 11, 10, 20));
    });

    test('from tomorrow once the time has passed, or today is read', () {
      expect(times(DateTime(2026, 11, 4, 20, 1)).first, DateTime(2026, 11, 5, 20));
      expect(times(DateTime(2026, 11, 4, 20)).first, DateTime(2026, 11, 5, 20), reason: 'not after: now');
      expect(times(DateTime(2026, 11, 4, 9), read: true).first, DateTime(2026, 11, 5, 20));
    });

    test('at the chosen minute, across the month end', () {
      final t = times(DateTime(2026, 11, 28, 5), minutes: 5 * 60 + 30);
      expect(t.first, DateTime(2026, 11, 28, 5, 30));
      expect(t[3], DateTime(2026, 12, 1, 5, 30));
    });
  });
}
