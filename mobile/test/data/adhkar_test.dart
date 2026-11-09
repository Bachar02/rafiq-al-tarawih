import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/data/adhkar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

void main() {
  final quran = loadQuran();
  final adhkar = loadAdhkar();
  final raw = File('assets/adhkar/adhkar.json').readAsStringSync();

  group('the bundled adhkar', () {
    test('five collections, each with its adhkar', () {
      expect({
        for (final c in AdhkarCollection.values) c: adhkar.of(c).length
      }, {
        AdhkarCollection.morning: 22,
        AdhkarCollection.evening: 21,
        AdhkarCollection.prayer: 11,
        AdhkarCollection.sleep: 13,
        AdhkarCollection.anytime: 16,
      });
    });

    test('the morning and the evening share one list; each says its own time', () {
      final morning = {for (final d in adhkar.of(AdhkarCollection.morning)) d.id: d};
      final evening = {for (final d in adhkar.of(AdhkarCollection.evening)) d.id: d};
      expect(morning.keys, contains('me19'), reason: 'morning only');
      expect(evening.keys, isNot(contains('me19')));
      expect(evening.keys, contains('me22'), reason: 'evening only');
      expect(morning.keys, isNot(contains('me22')));
      expect(morning['me03']!.arabic, startsWith('أَصْبَحْنَا'));
      expect(evening['me03']!.arabic, startsWith('أَمْسَيْنَا'));
      expect(evening['me03']!.meaning('en'), startsWith('We have reached the evening'));
      expect(evening['me03']!.meaning('fr'), startsWith('Nous voici au soir'));
      // Whatever says "this morning" has an evening wording.
      for (final id in evening.keys) {
        final m = morning[id];
        if (m?.arabic?.contains('أَصْبَح') ?? false) {
          expect(evening[id]!.arabic, isNot(m!.arabic), reason: '$id needs its evening words');
          expect(evening[id]!.arabic, matches(RegExp('أَمْسَ[يى]')), reason: id);
          expect(evening[id]!.meaning('en'), isNot(m.meaning('en')), reason: id);
        }
      }
    });

    test('the Quran is a reference into the app’s own text', () {
      final kursi = adhkar.of(AdhkarCollection.morning).first;
      expect(kursi.arabic, 'أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ');
      expect(kursi.passages.single.verses(quran).single.id, quran.verseId(2, 255));
      final quls = adhkar.of(AdhkarCollection.sleep).first;
      expect([
        for (final p in quls.passages) (p.surah, p.from, p.to, p.wholeSurah)
      ], [
        (112, 1, 4, true),
        (113, 1, 5, true),
        (114, 1, 6, true),
      ]);
      final baqarah = adhkar.of(AdhkarCollection.sleep)[2].passages.single;
      expect((baqarah.from, baqarah.to, baqarah.wholeSurah), (285, 286, false));
    });

    test('every dhikr has its meaning in English and French, every note three languages', () {
      for (final c in AdhkarCollection.values) {
        for (final d in adhkar.of(c)) {
          if (d.arabic != null) {
            expect(d.meanings.keys, containsAll(['en', 'fr']), reason: '${c.name}/${d.id}');
          }
          if (d.notes.isNotEmpty) expect(d.notes.keys, containsAll(['en', 'fr', 'ar']), reason: d.id);
          expect(d.meaning('ar'), isNull, reason: 'the Arabic is its own text');
          expect(adhkar.sourcesOf(d, 'ar'), everyElement(isNot(matches(RegExp('[a-z]')))), reason: d.id);
        }
      }
    });

    test('the tasbih after prayer is 33 each, before sleep 33, 33 and 34', () {
      int count(AdhkarCollection c, String id) => adhkar.of(c).firstWhere((d) => d.id == id).count;
      expect([
        for (final id in ['pr04', 'pr05', 'pr06']) count(AdhkarCollection.prayer, id)
      ], [
        33,
        33,
        33
      ]);
      expect([
        for (final id in ['sl08', 'sl09', 'sl10']) count(AdhkarCollection.sleep, id)
      ], [
        33,
        33,
        34
      ]);
    });

    test('notifications draw only on short adhkar for any time, never on the Quran', () {
      final pool = adhkar.forNotifications;
      expect(pool, hasLength(16));
      for (final d in pool) {
        expect(d.passages, isEmpty);
        // Tashkeel about doubles the characters: 250 is three short lines.
        expect(d.arabic!.length, lessThan(250), reason: '${d.id} must fit a notification');
      }
    });
  });

  group('a broken file fails loudly', () {
    Map<String, dynamic> json() => jsonDecode(raw) as Map<String, dynamic>;
    Map<String, dynamic> first(Map<String, dynamic> j) =>
        ((j['collections'] as Map<String, dynamic>)['prayer'] as List<dynamic>).first as Map<String, dynamic>;

    test('an unknown source', () {
      final j = json();
      first(j)['source'] = ['nobody'];
      expect(() => Adhkar.fromJson(jsonEncode(j), quran), throwsFormatException);
    });

    test('an ayah that does not exist', () {
      final j = json();
      first(j)['quran'] = ['2:287'];
      expect(() => Adhkar.fromJson(jsonEncode(j), quran), throwsFormatException);
    });

    test('a missing collection', () {
      final j = json();
      (j['collections'] as Map<String, dynamic>).remove('sleep');
      expect(() => Adhkar.fromJson(jsonEncode(j), quran), throwsFormatException);
    });

    test('a repeated id', () {
      final j = json();
      final list = (j['collections'] as Map<String, dynamic>)['prayer'] as List<dynamic>;
      (list[1] as Map<String, dynamic>)['id'] = first(j)['id'];
      expect(() => Adhkar.fromJson(jsonEncode(j), quran), throwsFormatException);
    });
  });

  group('a day of counts', () {
    final thrice = adhkar.of(AdhkarCollection.morning).firstWhere((d) => d.count == 3);
    const morning = AdhkarCollection.morning;

    test('counts up to the dhikr’s number and no further; collections are apart', () {
      var day = AdhkarDay(DateTime(2026, 11, 9, 7, 30));
      expect(day.day, DateTime(2026, 11, 9));
      for (var i = 0; i < 5; i++) {
        day = day.counted(morning, thrice);
      }
      expect(day.countOf(morning, thrice), 3);
      expect(day.isDone(morning, thrice), isTrue);
      expect(day.countOf(AdhkarCollection.evening, thrice), 0, reason: 'the evening is said again');
      expect(day.reset(morning).countOf(morning, thrice), 0);
    });

    test('kept on the phone; an unreadable record starts again', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = AdhkarStore(prefs);
      expect(store.load(), isNull);
      await store.save(AdhkarDay(DateTime(2026, 11, 9)).counted(morning, thrice));
      final back = store.load()!;
      expect(back.day, DateTime(2026, 11, 9));
      expect(back.countOf(morning, thrice), 1);
      await prefs.setString(AdhkarStore.key, '{not json');
      expect(store.load(), isNull);
      await prefs.setString(AdhkarStore.key, '{"v":1,"day":"2026-02-31","counts":{}}');
      expect(store.load(), isNull);
    });
  });
}
