import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/data/cities.dart';

import '../support/fakes.dart';

void main() {
  group('the bundled list', () {
    final cities = loadCities();

    test('reads whole: tens of thousands of towns, every country named', () {
      expect(cities.length, greaterThan(60000));
      for (final code in ['TN', 'DZ', 'MA', 'FR', 'SA', 'EG', 'ID', 'US']) {
        for (final language in ['en', 'fr', 'ar']) {
          expect(cities.countryName(code, language), isNotEmpty, reason: '$code in $language');
        }
      }
      expect(cities.countryName('TN', 'en'), 'Tunisia');
      expect(cities.countryName('TN', 'fr'), 'Tunisie');
      expect(cities.countryName('TN', 'ar'), 'تونس');
      expect(cities.countryName('ZZ', 'en'), isNull);
      expect(cities.countryName(null, 'en'), isNull);
    });

    test('no invisible marks, no tabs or line ends inside a name', () {
      final raw = File('assets/places/cities.tsv').readAsStringSync();
      expect(raw.contains('\r'), isFalse);
      // Zero-width and direction marks: U+200B..200F, 202A..202E, 2066..2069, FEFF.
      bool invisible(int c) =>
          (c >= 0x200B && c <= 0x200F) || (c >= 0x202A && c <= 0x202E) || (c >= 0x2066 && c <= 0x2069) || c == 0xFEFF;
      expect(raw.runes.where(invisible), isEmpty);
    });

    test('a capital comes before its namesakes', () {
      final tunis = cities.search('tunis').first;
      expect(tunis.name, 'Tunis');
      expect(tunis.countryCode, 'TN');
      expect(tunis.nameIn('ar'), 'تونس');
      expect(cities.search('paris').first.countryCode, 'FR');
      expect(cities.search('cairo').first.countryCode, 'EG');
    });

    test('found in Arabic and French, whatever the accents, hamzas and tashkeel', () {
      expect(cities.search('تونس').first.name, 'Tunis');
      expect(cities.search('القاهره').first.name, 'Cairo', reason: 'ه for ة');
      expect(cities.search('الْقَاهِرَة').first.name, 'Cairo', reason: 'tashkeel');
      expect(cities.search('le caire').first.name, 'Cairo');
      expect(cities.search('la mecque').first.name, 'Makkah');
      expect(cities.search('saint etienne').first.nameIn('fr'), 'Saint-Étienne');
      expect(cities.search('SFAX').first.countryCode, 'TN');
      expect(cities.search('  kairouan ').first.nameIn('ar'), 'القيروان');
    });

    test('the beginning of a name first, then a word of it', () {
      final found = cities.search('marsa').map((c) => foldPlaceName(c.name)).toList();
      expect(found.first, startsWith('marsa'));
      expect(found, contains('la marsa'));
      expect(found.indexOf('la marsa'), greaterThan(found.lastIndexWhere((n) => n.startsWith('marsa'))));
      expect(cities.search('marseille').map((c) => c.name), ['Marseille'], reason: 'a town, not its districts');
      expect(cities.search('zzzzqq'), isEmpty);
      expect(cities.search(''), isEmpty);
      expect(cities.search('a', limit: 5), hasLength(5));
    });

    test('the nearest town names a position', () {
      expect(cities.nearest(36.8065, 10.1815)!.name, 'Tunis');
      expect(cities.nearest(34.74, 10.76)!.name, 'Sfax');
      expect(cities.nearest(21.4225, 39.8262)!.name, 'Makkah');
      // Across the date line: Taveuni (Fiji) is at 180° east, give or take.
      expect(cities.nearest(-16.9, -179.95)!.countryCode, 'FJ');
    });

    test('a position the phone found: named, and kept to about a kilometre', () {
      final place = cities.located(36.80654321, 10.18154321);
      expect(place.latitude, 36.81);
      expect(place.longitude, 10.18);
      expect(place.fromLocation, isTrue);
      expect(place.countryCode, 'TN');
      expect(place.name('en'), 'Tunis');
      expect(place.name('ar'), 'تونس');
      expect(place.name('fr'), 'Tunis', reason: 'no French name of its own: the name');
    });

    test('a town the user chose: its own coordinates, and it stays put', () {
      final place = cities.chosen(cities.search('kairouan').first);
      expect(place.fromLocation, isFalse);
      expect(place.countryCode, 'TN');
      expect(place.latitude, closeTo(35.68, 0.01));
    });

    test('Jerusalem is one entry, in Palestine', () {
      final found = cities.search('jerusalem').where((c) => c.name == 'Jerusalem' && c.latitude > 31).toList();
      expect(found, hasLength(1));
      expect(found.single.countryCode, 'PS');
      expect(found.single.nameIn('ar'), 'القدس');
      expect(cities.countryName('PS', 'en'), 'Palestine');
    });
  });

  group('parsing', () {
    const countries = 'TN\tTunisia\tTunisie\tتونس\nFR\tFrance\t\t\n';

    test('a French or Arabic name left empty is the name itself', () {
      final cities = Cities.parse(
          (cities: 'Tunis\t\tتونس\tTN\t36.819\t10.166\nParis\t\t\tFR\t48.853\t2.349\n', countries: countries));
      expect(cities.length, 2);
      expect(cities.search('paris').single.nameIn('ar'), 'Paris');
      expect(cities.search('paris').single.names, {'en': 'Paris'});
      expect(cities.countryName('FR', 'ar'), 'France', reason: 'English when it has no other');
    });

    test('a row that is not a town fails the whole file', () {
      for (final row in [
        'Tunis\t\t\tTN\t36.819',
        'Tunis\t\t\tXX\t36.819\t10.166',
        'Tunis\t\t\tTN\tnorth\t10.166',
        'Tunis\t\t\tTN\t96.819\t10.166',
        '\t\t\tTN\t36.819\t10.166',
      ]) {
        expect(() => Cities.parse((cities: '$row\n', countries: countries)), throwsFormatException, reason: row);
      }
      expect(() => Cities.parse((cities: '', countries: 'TUN\tTunisia\t\t\n')), throwsFormatException);
    });

    test('no list: a position is named by its coordinates', () {
      final place = Cities.empty.located(36.8065, 10.1815);
      expect(place.name('en'), '36.81, 10.18');
      expect(place.countryCode, isNull);
      expect(Cities.empty.search('tunis'), isEmpty);
    });
  });

  test('names as search compares them', () {
    expect(foldPlaceName('Saint-Étienne'), 'saint etienne');
    expect(foldPlaceName("L'Haÿ-les-Roses"), 'lhay les roses');
    expect(foldPlaceName('  Sīdī   Bū Zayd '), 'sidi bu zayd');
    expect(foldPlaceName('İstanbul'), 'istanbul');
    expect(foldPlaceName('القَاهِرَة'), 'القاهره');
    expect(foldPlaceName('أريانة'), 'اريانه');
  });
}
