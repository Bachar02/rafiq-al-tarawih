/// Translations and tafsirs: the meaning of each ayah, from the bundled
/// `assets/texts/`.
///
/// Those files are built by `data/build_texts.py` from QuranEnc.com's own
/// databases, unchanged. QuranEnc's terms allow republishing on condition
/// that the text is not modified and that the publisher, QuranEnc.com and
/// the version are named: so the text is shown exactly as it comes, and its
/// [StudySource] (name, credit, version) travels with it onto the screen.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show TextDirection;

import 'quran.dart';

enum StudyKind { translation, tafsir }

/// One translation or tafsir, as the catalog describes it.
class StudySource {
  const StudySource({
    required this.key,
    required this.kind,
    required this.language,
    required this.direction,
    required this.names,
    required this.credits,
    required this.version,
    required this.updated,
    required this.url,
    required this.asset,
  });

  factory StudySource.fromJson(Map<String, dynamic> j) {
    final kind = StudyKind.values.asNameMap()[j['kind']];
    if (kind == null) throw FormatException('text ${j['key']} has an unknown kind ${j['kind']}');
    return StudySource(
      key: j['key'] as String,
      kind: kind,
      language: j['language'] as String,
      direction: j['direction'] == 'rtl' ? TextDirection.rtl : TextDirection.ltr,
      names: (j['name'] as Map<String, dynamic>).cast<String, String>(),
      credits: (j['credit'] as Map<String, dynamic>).cast<String, String>(),
      version: j['version'] as String,
      updated: j['updated'] as String,
      url: j['url'] as String,
      asset: j['asset'] as String? ?? 'assets/texts/${j['key']}.json',
    );
  }

  /// QuranEnc's key, e.g. `english_saheeh`.
  final String key;
  final StudyKind kind;

  /// The language the text is written in (`en`, `fr`, `ar`).
  final String language;
  final TextDirection direction;

  /// The text's name and its translator or publisher, by interface language.
  final Map<String, String> names;
  final Map<String, String> credits;

  /// QuranEnc's version, which its terms require us to name.
  final String version;

  /// When QuranEnc last updated it (YYYY-MM-DD).
  final String updated;

  /// The text's page on QuranEnc.com.
  final String url;

  /// Where the bundled text is.
  final String asset;

  String name(String languageCode) => names[languageCode] ?? names['en'] ?? key;
  String credit(String languageCode) => credits[languageCode] ?? credits['en'] ?? '';
}

/// The bundled texts, in order of preference within each kind.
class StudyCatalog {
  StudyCatalog(List<StudySource> sources) : sources = List.unmodifiable(sources);

  factory StudyCatalog.fromJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return StudyCatalog([
      for (final t in (json['texts'] as List).cast<Map<String, dynamic>>()) StudySource.fromJson(t),
    ]);
  }

  static final empty = StudyCatalog(const []);

  final List<StudySource> sources;

  List<StudySource> of(StudyKind kind) => [
        for (final s in sources)
          if (s.kind == kind) s,
      ];

  StudySource? byKey(String? key) {
    for (final s in sources) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// The text shown when the user has not chosen one: the [chosen] key if it
  /// is still bundled, else one in the interface language, else a
  /// translation in English or a tafsir in Arabic (the language every
  /// tafsir is first written in). Null if the catalog has none of [kind].
  StudySource? pick(StudyKind kind, {required String languageCode, String? chosen}) {
    final options = of(kind);
    if (options.isEmpty) return null;
    final saved = byKey(chosen);
    if (saved != null && saved.kind == kind) return saved;
    final fallback = kind == StudyKind.translation ? 'en' : 'ar';
    for (final language in [languageCode, fallback]) {
      for (final s in options) {
        if (s.language == language) return s;
      }
    }
    return options.first;
  }
}

/// One ayah's text, with the footnotes its translator gave it.
class StudyAyah {
  const StudyAyah(this.text, this.footnotes);

  /// As published (only surrounding whitespace is ignored on screen).
  final String text;

  /// Empty when there are none. Markers like `[1]` in [text] refer to them.
  final String footnotes;
}

/// A whole translation or tafsir: one [StudyAyah] per verse id.
class StudyText {
  StudyText._(this.key, this.version, this._ayahs);

  /// Parse a bundled text. Throws [FormatException] unless it is the
  /// expected text, complete: one entry for each of the 6236 ayahs, none
  /// empty. Top-level so it can run in an isolate ([compute]).
  static StudyText parse(({String raw, String key}) input) {
    final json = jsonDecode(input.raw) as Map<String, dynamic>;
    if (json['key'] != input.key) throw FormatException('expected text ${input.key}, found ${json['key']}');
    final ayahs = json['ayahs'] as List;
    if (ayahs.length != Quran.verseCount) {
      throw FormatException('text ${input.key} has ${ayahs.length} ayahs, expected ${Quran.verseCount}');
    }
    final out = <StudyAyah>[];
    for (final (i, a) in ayahs.indexed) {
      final pair = (a as List).cast<String>();
      if (pair.isEmpty || pair[0].trim().isEmpty) throw FormatException('text ${input.key}: ayah ${i + 1} is empty');
      out.add(StudyAyah(pair[0], pair.length > 1 ? pair[1] : ''));
    }
    return StudyText._(input.key, json['version'] as String? ?? '', List.unmodifiable(out));
  }

  final String key;
  final String version;
  final List<StudyAyah> _ayahs;

  StudyAyah ayah(int verseId) => _ayahs[verseId - 1];
}

typedef StudyTextLoader = Future<StudyText> Function(StudySource source);

/// Reads [source] from the app bundle. A tafsir is up to 2.5 MB of JSON, so it
/// is parsed off the UI thread.
Future<StudyText> loadBundledStudyText(StudySource source) async {
  final raw = await rootBundle.loadString(source.asset, cache: false);
  return compute(StudyText.parse, (raw: raw, key: source.key));
}
