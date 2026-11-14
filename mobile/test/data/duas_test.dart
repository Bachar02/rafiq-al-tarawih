import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/data/duas.dart';

import '../support/fakes.dart';

void main() {
  final quran = loadQuran();
  final duas = loadDuas();
  final raw = File('assets/duas/duas.json').readAsStringSync();

  group('the bundled duas', () {
    test('by purpose, each with its duas', () {
      expect([
        for (final c in duas.categories) c.id
      ], [
        'forgiveness',
        'distress',
        'guidance',
        'knowledge',
        'provision',
        'family',
        'health',
        'travel',
        'daily',
        'loss',
        'quran',
      ]);
      expect(duas.categories.fold<int>(0, (n, c) => n + c.duas.length), 46);
      for (final c in duas.categories) {
        expect(c.duas, isNotEmpty, reason: c.id);
        expect(c.title('ar'), isNot(c.title('en')), reason: c.id);
        expect(c.title('fr'), isNot(c.title('ar')), reason: c.id);
      }
      expect(duas.category('travel')!.title('fr'), 'Voyage');
      expect(duas.category('nothing'), isNull);
    });

    test('every dua in words has its meaning and how it is said, in English and French', () {
      for (final c in duas.categories) {
        for (final d in c.duas) {
          if (d.arabic == null) continue;
          expect(d.meanings.keys, containsAll(['en', 'fr']), reason: d.id);
          expect(d.transliterations.keys, containsAll(['en', 'fr']), reason: d.id);
          for (final language in ['en', 'fr']) {
            expect(d.transliteration(language), matches(RegExp(r'^[A-Za-z’ ,.\-]+$')), reason: '${d.id} $language');
          }
          expect(d.transliteration('ar'), isNull, reason: 'the Arabic is its own text');
          expect(d.meaning('ar'), isNull);
          if (d.notes.isNotEmpty) expect(d.notes.keys, containsAll(['en', 'fr', 'ar']), reason: d.id);
        }
      }
    });

    test('a dua from the Quran is a reference into the app’s own text, its source the Quran', () {
      final quranDuas = [
        for (final c in duas.categories)
          for (final d in c.duas)
            if (d.arabic == null) d
      ];
      expect(quranDuas, hasLength(15));
      for (final d in quranDuas) {
        expect(d.sources, ['quran'], reason: d.id);
        expect(d.passages, isNotEmpty, reason: d.id);
      }
      final adam = duas.category('forgiveness')!.duas.firstWhere((d) => d.id == 'fg03');
      expect(adam.passages.single.verses(quran).single.id, quran.verseId(7, 23));
      final musa = duas.category('guidance')!.duas.firstWhere((d) => d.id == 'gd04').passages.single;
      expect((musa.surah, musa.from, musa.to), (20, 25, 28));
    });

    test('sources by name in each language, Arabic in Arabic letters', () {
      final travel = duas.category('travel')!.duas.first;
      expect(duas.sourcesOf(travel, 'en'), ['Muslim']);
      expect(duas.sourcesOf(duas.category('family')!.duas.first, 'fr'), ['le Coran']);
      for (final c in duas.categories) {
        for (final d in c.duas) {
          expect(duas.sourcesOf(d, 'ar'), everyElement(isNot(matches(RegExp('[a-z]')))), reason: d.id);
        }
      }
    });

    test('said seven times where the hadith says so', () {
      final health = {for (final d in duas.category('health')!.duas) d.id: d.count};
      expect(health, {'hl01': 1, 'hl02': 7, 'hl03': 7, 'hl04': 1});
    });
  });

  group('a broken file fails, whole', () {
    Map<String, dynamic> file() => jsonDecode(raw) as Map<String, dynamic>;
    Duas parse(Map<String, dynamic> json) => Duas.fromJson(jsonEncode(json), quran);
    List<dynamic> categories(Map<String, dynamic> json) => json['categories'] as List<dynamic>;
    Map<String, dynamic> first(Map<String, dynamic> json) => categories(json).first as Map<String, dynamic>;

    test('the bundled one parses', () => expect(parse(file()).categories, hasLength(11)));

    test('another version', () {
      expect(() => parse(file()..['v'] = 2), throwsFormatException);
    });

    test('no categories', () {
      expect(() => parse(file()..['categories'] = []), throwsFormatException);
    });

    test('a purpose without its Arabic name', () {
      final json = file();
      (first(json)['title'] as Map<String, dynamic>).remove('ar');
      expect(() => parse(json), throwsFormatException);
    });

    test('a purpose without duas', () {
      final json = file();
      first(json)['duas'] = [];
      expect(() => parse(json), throwsFormatException);
    });

    test('an id used twice, even in two purposes', () {
      final json = file();
      final duaOfSecond = ((categories(json)[1] as Map<String, dynamic>)['duas'] as List<dynamic>).first as Map;
      duaOfSecond['id'] = 'fg01';
      expect(() => parse(json), throwsFormatException);
    });

    test('an unknown source, or an ayah that does not exist', () {
      var json = file();
      ((first(json)['duas'] as List<dynamic>).first as Map)['source'] = ['nobody'];
      expect(() => parse(json), throwsFormatException);
      json = file();
      ((first(json)['duas'] as List<dynamic>)[2] as Map)['quran'] = ['7:300'];
      expect(() => parse(json), throwsFormatException);
    });
  });
}
