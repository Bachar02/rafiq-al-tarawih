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
      expect(d.themeMode, ThemeMode.dark);

      await store.save(d.copyWith(serverAddress: ' 192.168.1.9:8765 ', textScale: 1.4, themeMode: ThemeMode.light));
      final back = store.load();
      expect(back.serverAddress, '192.168.1.9:8765');
      expect(back.textScale, 1.4);
      expect(back.themeMode, ThemeMode.light);
    });

    test('out-of-range or corrupt values fall back safely', () async {
      SharedPreferences.setMockInitialValues({'text_scale': 9.0, 'theme_mode': 'neon'});
      final s = SettingsStore(await SharedPreferences.getInstance()).load();
      expect(s.textScale, 1.6);
      expect(s.themeMode, ThemeMode.dark);
    });
  });
}
