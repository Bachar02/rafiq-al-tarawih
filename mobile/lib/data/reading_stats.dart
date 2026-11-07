/// What the reading chart shows, computed from the daily reading log.
library;

import 'khatm.dart' show dateOnly;
import 'reading_store.dart';

/// The chart's shade for a day's pages: 0 none, then 1–4, 5–9, 10–19, and
/// 20 or more (a juz).
int readingLevel(int pages) => pages <= 0
    ? 0
    : pages < 5
        ? 1
        : pages < 10
            ? 2
            : pages < 20
                ? 3
                : 4;

/// The day before [day] (calendar arithmetic, safe across daylight saving).
DateTime previousDay(DateTime day) => DateTime(day.year, day.month, day.day - 1);

/// The day after [day].
DateTime nextDay(DateTime day) => DateTime(day.year, day.month, day.day + 1);

/// Pages read per day, and the runs and totals the chart shows.
///
/// A day's pages are those counted in the log plus those still waiting for
/// review, once each: the same number as "Today" in the reader bar.
class ReadingStats {
  ReadingStats(ReadingLog log, ReadingLog pending, DateTime now) : today = dateOnly(now) {
    for (final source in [log, pending]) {
      for (final e in source.days.entries) {
        final day = ReadingLog.parseDay(e.key);
        if (day != null && e.value.isNotEmpty) (_pages[day] ??= <int>{}).addAll(e.value);
      }
    }
  }

  final DateTime today;
  final _pages = <DateTime, Set<int>>{};

  int pagesOn(DateTime day) => _pages[dateOnly(day)]?.length ?? 0;

  bool get readToday => pagesOn(today) > 0;

  /// Days in a row with reading, up to today. Today not read yet does not
  /// end the run: the day is not over.
  int get currentRun {
    var day = readToday ? today : previousDay(today);
    var run = 0;
    while (pagesOn(day) > 0) {
      run++;
      day = previousDay(day);
    }
    return run;
  }

  /// The longest run in the log (which keeps about a year).
  int get bestRun {
    var best = 0;
    for (final start in _pages.keys) {
      if (pagesOn(previousDay(start)) > 0) continue; // not the start of a run
      var run = 0;
      for (var day = start; pagesOn(day) > 0; day = nextDay(day)) {
        run++;
      }
      if (run > best) best = run;
    }
    return best;
  }

  int get daysThisYear => _pages.keys.where((d) => d.year == today.year && !d.isAfter(today)).length;

  int get pagesThisMonth => _pages.entries
      .where((e) => e.key.year == today.year && e.key.month == today.month)
      .fold(0, (n, e) => n + e.value.length);

  /// Days read from [first] to today.
  int daysSince(DateTime first) => _pages.keys.where((d) => !d.isBefore(first) && !d.isAfter(today)).length;
}
