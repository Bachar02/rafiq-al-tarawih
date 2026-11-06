import '../../data/quran.dart';
import '../../data/reading_store.dart';

/// Decides which pages were read: a page counts once it has been on screen
/// long enough to read it.
///
/// Time runs only while the reader is in view (the app in the foreground,
/// the Read tab shown, nothing over it) and goes to the page at the top of
/// the text. It adds up: a page read in two visits counts once the visits
/// together are long enough. A fling or the scrubber passes a page in a
/// fraction of a second, so it counts nothing, however far it goes.
///
/// Pure Dart, driven by the caller's clock, so it is tested without waiting.
class PageDwell {
  PageDwell(this.requiredFor);

  /// From the Quran: about [secondsPerWord] for each word on the page, at
  /// least [minimum]. A full Madinah page (about 130 words) takes some 20 s,
  /// Al-Fatiha's page about 5 s: a fast reader's pace, so honest reading
  /// always counts and skimming does not.
  factory PageDwell.forQuran(Quran quran) {
    final words = List.filled(Quran.pageCount + 1, 0);
    for (var page = 1; page <= Quran.pageCount; page++) {
      for (var id = quran.pages.start(page); id <= quran.pages.end(page); id++) {
        words[page] += quran.verse(id).text.split(' ').where((w) => w.isNotEmpty).length;
      }
    }
    return PageDwell((page) {
      final ms = (words[page] * secondsPerWord * 1000).round();
      return ms < minimum.inMilliseconds ? minimum : Duration(milliseconds: ms);
    });
  }

  static const secondsPerWord = 0.15;
  static const minimum = Duration(seconds: 4);

  /// Time a page must stay in view to count.
  final Duration Function(int page) requiredFor;

  int? _page;
  DateTime? _since;
  String? _day;
  final _spent = <int, Duration>{};
  final _read = <int>{};

  /// The page in view now, or null when nothing is (the app in the
  /// background, another tab, a sheet over the text). Returns the pages that
  /// have just been read.
  List<int> show(int? page, DateTime now) {
    final read = _account(now);
    _page = page;
    _since = page == null ? null : now;
    return read;
  }

  /// The time passed: returns the pages that have just been read.
  List<int> tick(DateTime now) {
    final read = _account(now);
    if (_page != null) _since = now;
    return read;
  }

  /// How long until the page in view counts, or null if it never will (no
  /// page in view, or it already counted).
  Duration? remaining(DateTime now) {
    final page = _page, since = _since;
    if (page == null || since == null || _read.contains(page)) return null;
    final left = requiredFor(page) - (_spent[page] ?? Duration.zero) - now.difference(since);
    return left.isNegative ? Duration.zero : left;
  }

  List<int> _account(DateTime now) {
    // A new day starts afresh: a page read again tomorrow is tomorrow's reading.
    final day = ReadingLog.dayKey(now);
    if (day != _day) {
      _day = day;
      _spent.clear();
      _read.clear();
    }
    final page = _page, since = _since;
    if (page == null || since == null || _read.contains(page)) return const [];
    final elapsed = now.difference(since);
    if (elapsed.isNegative) return const [];
    final spent = _spent[page] = (_spent[page] ?? Duration.zero) + elapsed;
    if (spent < requiredFor(page)) return const [];
    _read.add(page);
    return [page];
  }
}
