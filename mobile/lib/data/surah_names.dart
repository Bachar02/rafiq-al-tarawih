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

/// Interface languages. Arabic shows each surah's own name from the data.
enum NameLanguage { en, fr, ar }

class SurahNames {
  SurahNames._(this._en, this._fr, this._ar, [this.language = NameLanguage.en]);

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
    return SurahNames._(en, fr, [for (final s in quran.surahs) s.nameAr]);
  }

  /// Without the table: the data's own transliteration in every language.
  factory SurahNames.fallback(Quran quran) {
    final names = [for (final s in quran.surahs) s.nameTranslit];
    return SurahNames._(names, names, [for (final s in quran.surahs) s.nameAr]);
  }

  final List<String> _en;
  final List<String> _fr;
  final List<String> _ar;

  /// The interface language [of] uses by default.
  final NameLanguage language;

  /// The display name is the Arabic name itself: where the Arabic name is
  /// already on screen, it is not repeated.
  bool get isArabic => language == NameLanguage.ar;

  /// The same names, shown in [language] by default.
  SurahNames inLanguage(NameLanguage language) =>
      language == this.language ? this : SurahNames._(_en, _fr, _ar, language);

  /// The display name of surah [index] (1-based), in [language] or the default.
  String of(int index, [NameLanguage? language]) => switch (language ?? this.language) {
        NameLanguage.en => _en,
        NameLanguage.fr => _fr,
        NameLanguage.ar => _ar,
      }[index - 1];
}

/// Surahs matching [query]: number, display name, the data's
/// transliteration or English meaning, or the Arabic name.
List<Surah> searchSurahs(Quran quran, SurahNames names, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return quran.surahs;
  return quran.surahs
      .where((s) =>
          '${s.index}' == q ||
          // Every language's name, so any name the user knows finds the surah.
          names.of(s.index, NameLanguage.en).toLowerCase().contains(q) ||
          names.of(s.index, NameLanguage.fr).toLowerCase().contains(q) ||
          s.nameTranslit.toLowerCase().contains(q) ||
          s.nameEn.toLowerCase().contains(q) ||
          s.nameAr.contains(query.trim()))
      .toList();
}
