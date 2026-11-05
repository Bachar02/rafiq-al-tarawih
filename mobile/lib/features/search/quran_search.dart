/// One search field for the whole Quran: references ("2:255"), pages
/// ("page 50"), juz ("juz 30"), surah names (any language the app knows),
/// and Arabic text.
///
/// Arabic text is matched in the Simple Clean text after the same
/// [normalize] the recognition engine uses, so a query typed with or
/// without tashkeel, hamza seats or alef forms finds the same ayahs. Pure
/// Dart: no Flutter, tested directly.
library;

import '../../core/text/normalize.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';

/// A place to open.
sealed class SearchTarget {
  const SearchTarget(this.verseId);

  /// Where to open the reader.
  final int verseId;
}

/// `surah:ayah`.
final class AyahTarget extends SearchTarget {
  const AyahTarget(super.verseId);
}

final class SurahTarget extends SearchTarget {
  const SurahTarget(super.verseId, this.surah);
  final int surah;
}

final class JuzTarget extends SearchTarget {
  const JuzTarget(super.verseId, this.juz);
  final int juz;
}

final class PageTarget extends SearchTarget {
  const PageTarget(super.verseId, this.page);
  final int page;
}

class SearchResults {
  const SearchResults({this.targets = const [], this.ayahs = const [], this.ayahTotal = 0, this.textTooShort = false});

  static const empty = SearchResults();

  /// References, surahs, juz and pages the query names, most specific first.
  final List<SearchTarget> targets;

  /// Ayahs whose text contains the query, in mushaf order, at most
  /// [QuranSearch.maxAyahs].
  final List<Verse> ayahs;

  /// How many ayahs matched in all.
  final int ayahTotal;

  /// Arabic was typed, but too little to search the text yet.
  final bool textTooShort;

  bool get isEmpty => targets.isEmpty && ayahs.isEmpty;
}

class QuranSearch {
  QuranSearch(this.quran, this.names);

  final Quran quran;
  final SurahNames names;

  static const maxAyahs = 200;

  /// Fewer letters than this match too much to be useful.
  static const minLetters = 2;

  /// Each verse's matching text, built once on the first text search.
  late final List<String> _texts = [for (final v in quran.verses) normalize(v.text)];

  static final _reference = RegExp(r'^(\d{1,3})\s*[:.\-/ ]\s*(\d{1,3})$');
  static final _page = RegExp(r'^(?:page|pages|pg|p|صفحة|الصفحة|ص)\s*\.?\s*(\d{1,3})$', caseSensitive: false);
  static final _juz = RegExp(r'^(?:juz|juzz|jouz|para|j|جزء|الجزء|ج)\s*\.?\s*(\d{1,2})$', caseSensitive: false);
  static final _number = RegExp(r'^\d{1,3}$');
  static final _arabicLetter = RegExp('[ء-ي]');

  SearchResults search(String raw) {
    final query = westernDigits(raw).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.isEmpty) return SearchResults.empty;

    final reference = _reference.firstMatch(query);
    if (reference != null) {
      final id = quran.verseId(int.parse(reference[1]!), int.parse(reference[2]!));
      return SearchResults(targets: [if (id != null) AyahTarget(id)]);
    }
    final page = _page.firstMatch(query);
    if (page != null) return SearchResults(targets: _present([_pageTarget(int.parse(page[1]!))]));
    final juz = _juz.firstMatch(query);
    if (juz != null) return SearchResults(targets: _present([_juzTarget(int.parse(juz[1]!))]));
    if (_number.hasMatch(query)) {
      final n = int.parse(query);
      return SearchResults(
        targets: _present([
          if (n >= 1 && n <= quran.surahs.length) SurahTarget(quran.surah(n).firstVerseId, n),
          _juzTarget(n),
          _pageTarget(n),
        ]),
      );
    }

    final surahs = [for (final s in searchSurahs(quran, names, query)) SurahTarget(s.firstVerseId, s.index)];
    if (!_arabicLetter.hasMatch(query)) return SearchResults(targets: surahs);

    final needle = normalize(query);
    if (needle.replaceAll(' ', '').length < minLetters) {
      return SearchResults(targets: surahs, textTooShort: true);
    }
    final ayahs = <Verse>[];
    var total = 0;
    for (var i = 0; i < _texts.length; i++) {
      if (_texts[i].contains(needle)) {
        total++;
        if (ayahs.length < maxAyahs) ayahs.add(quran.verses[i]);
      }
    }
    return SearchResults(targets: surahs, ayahs: List.unmodifiable(ayahs), ayahTotal: total);
  }

  static List<SearchTarget> _present(List<SearchTarget?> targets) => [
        for (final t in targets)
          if (t != null) t
      ];

  PageTarget? _pageTarget(int page) =>
      page >= 1 && page <= quran.pages.count ? PageTarget(quran.pages.start(page), page) : null;

  JuzTarget? _juzTarget(int juz) => juz >= 1 && juz <= quran.juzs.count ? JuzTarget(quran.juzs.start(juz), juz) : null;
}

/// Arabic-Indic (٠١٢) and Eastern Arabic-Indic (۰۱۲) digits as 0-9, so
/// "٢:٢٥٥" works like "2:255".
String westernDigits(String s) => s.replaceAllMapped(RegExp('[٠-٩۰-۹]'), (m) {
      final c = m[0]!.codeUnitAt(0);
      return String.fromCharCode(0x30 + (c >= 0x06F0 ? c - 0x06F0 : c - 0x0660));
    });
