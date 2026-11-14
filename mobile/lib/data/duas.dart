/// The duas: supplications for the needs of a life (forgiveness, worry and
/// distress, guidance, knowledge, provision, family, illness, travel, the
/// home and the day, loss), from the bundled `assets/duas/duas.json`.
///
/// Each is a [Dhikr] like the adhkar: its Arabic, how it is said in Latin
/// letters, its meaning, and who reports it. A dua from the Quran is a
/// reference, shown from the app's own Quran text (assets/duas/NOTICE.txt).
library;

import 'dart:convert';

import 'adhkar.dart';
import 'quran.dart';

/// One purpose, and its duas in order.
class DuaCategory {
  const DuaCategory({required this.id, required this.titles, required this.duas});

  final String id;

  /// Its name by language (`en`, `fr`, `ar`).
  final Map<String, String> titles;
  final List<Dhikr> duas;

  String title(String languageCode) => titles[languageCode] ?? titles['en']!;
}

/// The bundled duas.
class Duas {
  Duas._(this.categories, this.sourceNames);

  /// No duas (a build without the file): the screen says nothing is there.
  static final empty = Duas._(const [], const {});

  final List<DuaCategory> categories;

  /// Each source's name by language: `{bukhari: {en: al-Bukhari, ...}}`.
  final Map<String, Map<String, String>> sourceNames;

  DuaCategory? category(String id) => categories.where((c) => c.id == id).firstOrNull;

  /// The sources of [dua] by name, in [languageCode].
  List<String> sourcesOf(Dhikr dua, String languageCode) => sourceNamesOf(sourceNames, dua.sources, languageCode);

  /// Parses and checks the file: categories with a name in three languages
  /// and at least one dua, ids unique across the file, and each dua as the
  /// adhkar are checked ([Dhikr.fromJson]). Throws [FormatException]: a
  /// broken file must fail the build's tests, not show a half-empty screen.
  factory Duas.fromJson(String raw, Quran quran) {
    const file = 'duas.json';
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic> || json['v'] != 1) throw const FormatException('$file: not version 1');
    final sources = parseSourceNames(json['sources'], file);
    final list = json['categories'];
    if (list is! List || list.isEmpty) throw const FormatException('$file: no categories');
    final ids = <String>{};
    final categories = <DuaCategory>[];
    for (final c in list.cast<Map<String, dynamic>>()) {
      final id = c['id'];
      if (id is! String || !ids.add('category/$id')) throw FormatException('$file: category id "$id"');
      final titles = (c['title'] as Map<String, dynamic>? ?? const {}).cast<String, String>();
      for (final language in const ['en', 'fr', 'ar']) {
        if ((titles[language] ?? '').isEmpty) throw FormatException('$file: category $id has no $language name');
      }
      final items = c['duas'];
      if (items is! List || items.isEmpty) throw FormatException('$file: category $id has no duas');
      final duas = [
        for (final j in items.cast<Map<String, dynamic>>())
          Dhikr.fromJson(j, quran: quran, sources: sources, file: file),
      ];
      for (final d in duas) {
        if (!ids.add(d.id)) throw FormatException('$file: the id ${d.id} is repeated');
      }
      categories.add(DuaCategory(id: id, titles: Map.unmodifiable(titles), duas: List.unmodifiable(duas)));
    }
    return Duas._(List.unmodifiable(categories), Map.unmodifiable(sources));
  }
}
