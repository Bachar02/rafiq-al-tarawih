/// A khatm: reading the whole Quran, all 604 pages, by a chosen date.
///
/// The plan keeps the day each page was first read during it, so it does not
/// depend on the reading log (kept only [ReadingLog.keepDays]) and a page read
/// twice counts once. Today's target adapts: what is left, spread over the
/// days left, so reading ahead lowers tomorrow's target and falling behind
/// raises it.
library;

import 'package:flutter/foundation.dart';

import 'quran.dart';
import 'reading_store.dart';

/// [local]'s calendar day, at midnight.
DateTime dateOnly(DateTime local) => DateTime(local.year, local.month, local.day);

/// The `yyyy-mm-dd` key of a day (as [ReadingLog.dayKey] writes it), or null.
DateTime? parseDayKey(Object? key) {
  if (key is! String) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (m == null) return null;
  final day = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return ReadingLog.dayKey(day) == key ? day : null; // rejects 2026-02-31
}

/// Whole days from [from] to [to] (calendar days, whatever the clock change).
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// The one active plan. Immutable.
@immutable
class KhatmPlan {
  KhatmPlan({
    required DateTime startedOn,
    required DateTime endsOn,
    required this.startPage,
    Map<int, String> pages = const {},
  })  : startedOn = dateOnly(startedOn),
        endsOn = dateOnly(endsOn),
        pages = Map.unmodifiable(pages);

  /// The first day, and the last day (inclusive).
  final DateTime startedOn, endsOn;

  /// Where the reading order begins: the plan reads on from here, then from
  /// page 1 back up to it.
  final int startPage;

  /// The day (`yyyy-mm-dd`) each page was first read during the plan.
  final Map<int, String> pages;

  int get read => pages.length;
  int get remaining => Quran.pageCount - pages.length;
  bool get complete => remaining == 0;

  /// The planned number of days.
  int get length => daysBetween(startedOn, endsOn) + 1;

  /// Pages first read on [day].
  int readOn(DateTime day) {
    final key = ReadingLog.dayKey(day);
    return pages.values.where((d) => d == key).length;
  }

  /// Days left including [today]; at least one, so a late plan asks for the rest today.
  int daysLeft(DateTime today) {
    final left = daysBetween(today, endsOn) + 1;
    return left < 1 ? 1 : left;
  }

  /// [today] is after the last planned day.
  bool overdue(DateTime today) => daysBetween(endsOn, today) > 0;

  /// The pages to read on [today]: what was left this morning, over the days
  /// left. Reading today does not shrink today's target.
  int todayTarget(DateTime today) => ((remaining + readOn(today)) / daysLeft(today)).ceil();

  /// The first unread page in reading order, or null when every page is read.
  int? get nextPage => nextPageCounting(const []);

  /// [nextPage], counting [alsoRead] as read too: the pages the reader saw
  /// that the user has not counted yet.
  int? nextPageCounting(Iterable<int> alsoRead) {
    final extra = alsoRead is Set<int> ? alsoRead : alsoRead.toSet();
    for (var i = 0; i < Quran.pageCount; i++) {
      final page = (startPage - 1 + i) % Quran.pageCount + 1;
      if (!pages.containsKey(page) && !extra.contains(page)) return page;
    }
    return null;
  }

  /// This plan with [newPages] read on [day]; pages read before keep their day.
  KhatmPlan reading(DateTime day, Iterable<int> newPages) {
    final key = ReadingLog.dayKey(day);
    final added = {...pages};
    for (final p in newPages) {
      if (p >= 1 && p <= Quran.pageCount) added.putIfAbsent(p, () => key);
    }
    return added.length == pages.length ? this : copyWith(pages: added);
  }

  /// This plan with [unread] no longer read (the page map's correction).
  KhatmPlan forgetting(Iterable<int> unread) {
    final drop = unread.toSet();
    if (!drop.any(pages.containsKey)) return this;
    return copyWith(pages: {
      for (final e in pages.entries)
        if (!drop.contains(e.key)) e.key: e.value
    });
  }

  KhatmPlan copyWith({DateTime? endsOn, Map<int, String>? pages}) =>
      KhatmPlan(startedOn: startedOn, endsOn: endsOn ?? this.endsOn, startPage: startPage, pages: pages ?? this.pages);

  /// Pages grouped by day: compact (a 604-entry map would repeat each date).
  Map<String, Object> toJson() {
    final byDay = <String, List<int>>{};
    for (final e in pages.entries) {
      (byDay[e.value] ??= []).add(e.key);
    }
    return {
      'v': 1,
      'start': ReadingLog.dayKey(startedOn),
      'end': ReadingLog.dayKey(endsOn),
      'from': startPage,
      'pages': {for (final e in byDay.entries) e.key: (e.value..sort())},
    };
  }

  /// Null if the plan itself is unreadable. Pages that are not are left out
  /// and [onDropped] is called, so the store can keep the original.
  static KhatmPlan? fromJson(Object? json, {VoidCallback? onDropped}) {
    if (json is! Map || json['v'] != 1) return null;
    final start = parseDayKey(json['start']), end = parseDayKey(json['end']);
    final from = json['from'], days = json['pages'];
    if (start == null || end == null || end.isBefore(start)) return null;
    if (from is! int || from < 1 || from > Quran.pageCount || days is! Map) return null;
    final pages = <int, String>{};
    var dropped = false;
    for (final e in days.entries) {
      final list = e.value;
      if (parseDayKey(e.key) == null || list is! List) {
        dropped = true;
        continue;
      }
      for (final p in list) {
        if (p is int && p >= 1 && p <= Quran.pageCount) {
          final earlier = pages[p];
          if (earlier == null || (e.key as String).compareTo(earlier) < 0) pages[p] = e.key as String;
        } else {
          dropped = true;
        }
      }
    }
    if (dropped) onDropped?.call();
    return KhatmPlan(startedOn: start, endsOn: end, startPage: from, pages: pages);
  }

  @override
  bool operator ==(Object other) =>
      other is KhatmPlan &&
      other.startedOn == startedOn &&
      other.endsOn == endsOn &&
      other.startPage == startPage &&
      mapEquals(other.pages, pages);

  @override
  int get hashCode => Object.hash(startedOn, endsOn, startPage, pages.length);
}

/// Where to continue reading, as one ayah: the reading reminder names it,
/// tapping the reminder opens it, and the khatm's Continue goes there.
///
/// In a [khatm], its next page (pages read but not yet counted, [uncounted],
/// count as read): the ayah the reader stopped at ([position]) if it is on
/// that page, since the user left in the middle of it, else the page's
/// first ayah. Without a khatm, or with every page read, the reader's place.
int resumeVerse(Quran quran, {required int position, KhatmPlan? khatm, Iterable<int> uncounted = const []}) {
  final page = khatm?.nextPageCounting(uncounted);
  if (page == null) return position;
  return quran.pageOf(position) == page ? position : quran.pages.start(page);
}

/// A completed khatm.
@immutable
class KhatmRecord {
  KhatmRecord({required DateTime startedOn, required DateTime completedOn})
      : startedOn = dateOnly(startedOn),
        completedOn = dateOnly(completedOn);

  final DateTime startedOn, completedOn;

  /// Days it took, counting the first and the last.
  int get days => daysBetween(startedOn, completedOn) + 1;

  Map<String, Object> toJson() => {'start': ReadingLog.dayKey(startedOn), 'done': ReadingLog.dayKey(completedOn)};

  static KhatmRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final start = parseDayKey(json['start']), done = parseDayKey(json['done']);
    if (start == null || done == null || done.isBefore(start)) return null;
    return KhatmRecord(startedOn: start, completedOn: done);
  }

  @override
  bool operator ==(Object other) =>
      other is KhatmRecord && other.startedOn == startedOn && other.completedOn == completedOn;

  @override
  int get hashCode => Object.hash(startedOn, completedOn);
}

/// The active plan, if any, and every finished khatm (newest first).
@immutable
class KhatmBook {
  KhatmBook({this.active, List<KhatmRecord> finished = const []}) : finished = List.unmodifiable(finished);

  final KhatmPlan? active;
  final List<KhatmRecord> finished;

  static final empty = KhatmBook();

  Map<String, Object?> toJson() => {
        'v': 1,
        'active': active?.toJson(),
        'finished': [for (final r in finished) r.toJson()],
      };

  /// Null if the record is unreadable as a whole; unreadable parts are left
  /// out and [onDropped] is called.
  static KhatmBook? fromJson(Object? json, {VoidCallback? onDropped}) {
    if (json is! Map || json['v'] != 1) return null;
    final rawActive = json['active'], rawFinished = json['finished'];
    if (rawFinished is! List) return null;
    var dropped = false;
    void drop() => dropped = true;
    final active = rawActive == null ? null : KhatmPlan.fromJson(rawActive, onDropped: drop);
    if (rawActive != null && active == null) dropped = true;
    final finished = <KhatmRecord>[];
    for (final r in rawFinished) {
      final record = KhatmRecord.fromJson(r);
      record == null ? dropped = true : finished.add(record);
    }
    finished.sort((a, b) => b.completedOn.compareTo(a.completedOn));
    if (dropped) onDropped?.call();
    return KhatmBook(active: active, finished: finished);
  }

  @override
  bool operator ==(Object other) =>
      other is KhatmBook && other.active == active && listEquals(other.finished, finished);

  @override
  int get hashCode => Object.hash(active, finished.length);
}
