import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/data/surah_names.dart';

import '../support/fakes.dart';

void main() {
  test('the curated table matches the Quran data, row for row', () {
    final names = loadSurahNames(); // throws if any index, Arabic name or transliteration differs
    expect(names.of(1), 'Al-Fatiha');
    expect(names.of(36), 'Ya-Sin');
    expect(names.of(93), 'Ad-Duha');
    expect(names.of(93, NameLanguage.fr), 'Ad-Douha');
    expect(names.of(114), 'An-Nas');
  });

  test('a table that drifts from the data is rejected', () {
    final raw = File('assets/data/surah-names.json').readAsStringSync().replaceFirst('"الضحى"', '"الليل"');
    expect(() => SurahNames.fromJson(raw, loadQuran()), throwsFormatException);
  });

  test('without the table, the data\'s own transliteration is used', () {
    final names = SurahNames.fallback(loadQuran());
    expect(names.of(93), loadQuran().surah(93).nameTranslit);
  });

  test('the Quran data itself is untouched by the table', () {
    expect(loadQuran().surah(93).nameTranslit, 'Ad-Dhuhaa');
    expect(loadQuran().surah(93).nameAr, 'الضحى');
  });
}
