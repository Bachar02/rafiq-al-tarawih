import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/data/quran.dart';
import 'package:rafiq/data/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('bundled Quran', () {
    late Quran quran;
    setUpAll(() => quran = Quran.fromJson(File('assets/quran/quran.json').readAsStringSync()));

    test('is complete and consistent', () {
      expect(quran.surahs, hasLength(114));
      expect(quran.verses, hasLength(6236));
      expect(quran.juzCount, 30);
      for (final s in quran.surahs) {
        final verses = quran.surahVerses(s.index);
        expect(verses, hasLength(s.ayahCount));
        expect(verses.first.ayah, 1);
        expect(verses.every((v) => v.surah == s.index), isTrue);
      }
    });

    test('lookups', () {
      expect(quran.surah(93).nameTranslit, isNotEmpty);
      expect(quran.verse(1).text, 'بسم الله الرحمن الرحيم');
      expect(quran.surah(2).hasBasmala, isTrue);
      expect(quran.surah(9).hasBasmala, isFalse);
      expect(quran.juzOf(1), 1);
      expect(quran.juzOf(6236), 30);
      expect(quran.juzStartSurah(30).index, 78);
    });

    test('juz, page and hizb-quarter starts follow the printed Madinah mushaf', () {
      expect(quran.pages.count, 604);
      expect(quran.quarters.count, 240);
      // The page each juz starts on, as printed (juz 7 and 11 are irregular).
      const juzPages = [
        1, 22, 42, 62, 82, 102, 121, 142, 162, 182, 201, 222, 242, 262, 282, //
        302, 322, 342, 362, 382, 402, 422, 442, 462, 482, 502, 522, 542, 562, 582
      ];
      expect([for (var j = 1; j <= 30; j++) quran.pageOf(quran.juzs.start(j))], juzPages);
      int page(int s, int a) => quran.pageOf(quran.verseId(s, a)!);
      expect(page(2, 255), 42);
      expect(page(18, 1), 293);
      expect(page(36, 1), 440);
      expect(page(67, 1), 562);
      expect(page(114, 6), 604);
      // Every juz is exactly eight hizb quarters.
      for (var j = 1; j <= 30; j++) {
        expect(quran.juzs.start(j), quran.quarters.start(8 * (j - 1) + 1));
      }
    });

    test('binary-search lookups agree with a linear scan for every verse', () {
      for (final d in [quran.juzs, quran.pages, quran.quarters]) {
        var expected = 0;
        for (var id = 1; id <= Quran.verseCount; id++) {
          if (expected < d.count && d.start(expected + 1) == id) expected++;
          expect(d.of(id), expected, reason: '${d.name} of verse $id');
          expect(d.isStart(id), d.start(expected) == id);
        }
        for (var i = 1; i <= d.count; i++) {
          expect(d.of(d.end(i)), i);
          expect(d.start(i) <= d.end(i), isTrue);
        }
      }
    });

    test('verse ids by reference, and out-of-range references', () {
      expect(quran.verseId(1, 1), 1);
      expect(quran.verseId(2, 255), 262);
      expect(quran.verseId(114, 6), Quran.verseCount);
      expect(quran.verseId(2, 287), isNull);
      expect(quran.verseId(0, 1), isNull);
      expect(quran.verseId(115, 1), isNull);
      expect(quran.verseId(1, 0), isNull);
    });

    test('rejects marks that are missing or out of order', () {
      final json = jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>;
      final noPages = Map.of(json)..remove('pages');
      expect(() => Quran.fromJson(jsonEncode(noPages)), throwsFormatException);
      final quarters = [...(json['hizb_quarters'] as List)];
      final moved = quarters.removeAt(3);
      quarters.insert(4, moved);
      final swapped = Map.of(json)..['hizb_quarters'] = quarters;
      expect(() => Quran.fromJson(jsonEncode(swapped)), throwsFormatException);
    });

    test('rejects an incomplete file', () {
      expect(() => Quran.fromJson('{"surahs":[],"verses":[],"juzs":[]}'), throwsFormatException);
    });
  });

  group('settings', () {
    test('defaults, then round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore(await SharedPreferences.getInstance());
      final d = store.load();
      expect(d.serverAddress, AppSettings.defaultServerAddress);
      expect(d.keepScreenOn, isTrue);
      // The reader follows the phone; Taraweeh mode is dark on its own.
      expect(d.themeMode, ThemeMode.system);
      expect(d.darkDuringTaraweeh, isTrue);
      expect(d.taraweehIntroSeen, isFalse);

      await store.save(d.copyWith(serverAddress: ' 192.168.1.9:8765 ', textScale: 1.4, themeMode: ThemeMode.light));
      final back = store.load();
      expect(back.serverAddress, '192.168.1.9:8765');
      expect(back.textScale, 1.4);
      expect(back.themeMode, ThemeMode.light);
    });

    test('a theme saved by an earlier version is kept', () async {
      // v1 defaulted to dark and saved every field on any change.
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark', 'text_scale': 1.2});
      final s = SettingsStore(await SharedPreferences.getInstance()).load();
      expect(s.themeMode, ThemeMode.dark);
      expect(s.textScale, 1.2);
      expect(s.darkDuringTaraweeh, isTrue);
    });

    test('Taraweeh settings round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore(await SharedPreferences.getInstance());
      await store.save(store.load().copyWith(darkDuringTaraweeh: false, taraweehIntroSeen: true));
      final back = store.load();
      expect(back.darkDuringTaraweeh, isFalse);
      expect(back.taraweehIntroSeen, isTrue);
    });

    test('out-of-range or corrupt values fall back safely', () async {
      SharedPreferences.setMockInitialValues({'text_scale': 9.0, 'theme_mode': 'neon', 'word_stale_seconds': 0.1});
      final s = SettingsStore(await SharedPreferences.getInstance()).load();
      expect(s.textScale, 1.6);
      expect(s.themeMode, ThemeMode.system);
      expect(s.wordStaleSeconds, AppSettings.defaultWordStaleSeconds, reason: 'not one of the offered thresholds');
    });

    test('word highlighting: off by default, 1.5 s, and both round-trip', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore(await SharedPreferences.getInstance());
      final d = store.load();
      expect(d.wordHighlight, isFalse);
      expect(d.wordStaleSeconds, 1.5);
      await store.save(d.copyWith(wordHighlight: true, wordStaleSeconds: 2.0));
      final back = store.load();
      expect(back.wordHighlight, isTrue);
      expect(back.wordStaleSeconds, 2.0);
    });
  });
}
