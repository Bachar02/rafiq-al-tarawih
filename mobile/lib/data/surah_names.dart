/// Curated display names for the 114 surahs, from the bundled
/// `assets/data/surah-names.json` (Rubric handoff, draft for native review).
///
/// Display only: the app keeps surah indexes as identifiers and the Quran
/// data (`quran.json`) is never changed. Each row carries the data's own
/// Arabic name and transliteration, which [SurahNames.fromJson] checks
/// against the loaded [Quran] so the two can never drift apart silently.
library;

import 'dart:convert';

import 'quran.dart';

/// Interface languages with a display-name column.
enum NameLanguage { en, fr }

class SurahNames {
  SurahNames._(this._en, this._fr);

  /// Parse the table. Throws [FormatException] if it does not match [quran].
  factory SurahNames.fromJson(String raw, Quran quran) {
    final rows = ((jsonDecode(raw) as Map<String, dynamic>)['surahs'] as List).cast<Map<String, dynamic>>();
    if (rows.length != quran.surahs.length) {
      throw FormatException('surah-names.json has ${rows.length} rows, the Quran ${quran.surahs.length} surahs');
    }
    final en = <String>[], fr = <String>[];
    for (final (i, row) in rows.indexed) {
      final surah = quran.surahs[i];
      if (row['index'] != surah.index || row['name_ar'] != surah.nameAr || row['data_translit'] != surah.nameTranslit) {
        throw FormatException('surah-names.json row ${i + 1} does not match quran.json');
      }
      en.add(row['en'] as String);
      fr.add(row['fr'] as String);
    }
    return SurahNames._(en, fr);
  }

  /// Without the table: the data's own transliteration in every language.
  factory SurahNames.fallback(Quran quran) {
    final names = [for (final s in quran.surahs) s.nameTranslit];
    return SurahNames._(names, names);
  }

  final List<String> _en;
  final List<String> _fr;

  /// The display name of surah [index] (1-based) in [language].
  String of(int index, [NameLanguage language = NameLanguage.en]) =>
      (language == NameLanguage.fr ? _fr : _en)[index - 1];
}

/// Surahs matching [query]: number, display name, the data's
/// transliteration or English meaning, or the Arabic name.
List<Surah> searchSurahs(Quran quran, SurahNames names, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return quran.surahs;
  return quran.surahs
      .where((s) =>
          '${s.index}' == q ||
          names.of(s.index).toLowerCase().contains(q) ||
          s.nameTranslit.toLowerCase().contains(q) ||
          s.nameEn.toLowerCase().contains(q) ||
          s.nameAr.contains(query.trim()))
      .toList();
}
