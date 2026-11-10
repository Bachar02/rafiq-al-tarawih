/// The towns the prayer times can be set for: the bundled
/// `assets/places/cities.tsv` and `countries.tsv` (GeoNames, CC BY 4.0;
/// built by `data/build_places.py`, see `assets/places/NOTICE.txt`).
///
/// The list is what lets the app name where the phone is, and offer a town
/// to someone who would rather not share a position, without asking any
/// server: a position never leaves the phone.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../core/text/normalize.dart' show letterMap;
import 'prayer_settings.dart';

/// The bundled list, parsed off the UI thread (some 60,000 rows).
Future<Cities> loadBundledCities() async {
  final cities = await rootBundle.loadString('assets/places/cities.tsv');
  final countries = await rootBundle.loadString('assets/places/countries.tsv');
  return compute(Cities.parse, (cities: cities, countries: countries));
}

/// One town of the list.
class City {
  const City({
    required this.name,
    required this.french,
    required this.arabic,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
  });

  /// The name GeoNames lists it under (the local or the English name).
  final String name;

  /// Its French and Arabic names, where they differ and are known.
  final String? french;
  final String? arabic;

  final String countryCode;
  final double latitude;
  final double longitude;

  String nameIn(String languageCode) => switch (languageCode) {
        'ar' => arabic ?? name,
        'fr' => french ?? name,
        _ => name,
      };

  /// The town's names by language, as a [Place] keeps them.
  Map<String, String> get names => {
        'en': name,
        if (french != null) 'fr': french!,
        if (arabic != null) 'ar': arabic!,
      };
}

/// The bundled towns and countries.
class Cities {
  Cities._(this._cities, this._keys, this._countries);

  /// No list (a build without the files): a position still gives prayer
  /// times, named by its coordinates.
  static final empty = Cities._(const [], const [], const {});

  /// Most populous first.
  final List<City> _cities;

  /// Each town's names folded for search, one per line.
  final List<String> _keys;

  /// Country code -> its names by language.
  final Map<String, Map<String, String>> _countries;

  int get length => _cities.length;

  /// Parses and checks the two files. Throws [FormatException] on a row
  /// that is not a town or a country: a broken file must fail the build's
  /// tests, not send someone's prayer times to the wrong place.
  factory Cities.parse(({String cities, String countries}) raw) {
    final countries = <String, Map<String, String>>{};
    for (final line in raw.countries.split('\n')) {
      if (line.isEmpty) continue;
      final f = line.split('\t');
      if (f.length != 4 || f[0].length != 2 || f[1].isEmpty) throw FormatException('countries.tsv: bad row "$line"');
      countries[f[0]] = {
        'en': f[1],
        if (f[2].isNotEmpty) 'fr': f[2],
        if (f[3].isNotEmpty) 'ar': f[3],
      };
    }
    final cities = <City>[];
    final keys = <String>[];
    for (final line in raw.cities.split('\n')) {
      if (line.isEmpty) continue;
      final f = line.split('\t');
      final latitude = f.length == 6 ? double.tryParse(f[4]) : null;
      final longitude = f.length == 6 ? double.tryParse(f[5]) : null;
      if (latitude == null ||
          longitude == null ||
          f[0].isEmpty ||
          !countries.containsKey(f[3]) ||
          latitude < -90 ||
          latitude > 90 ||
          longitude < -180 ||
          longitude > 180) {
        throw FormatException('cities.tsv: bad row "$line"');
      }
      final city = City(
        name: f[0],
        french: f[1].isEmpty ? null : f[1],
        arabic: f[2].isEmpty ? null : f[2],
        countryCode: f[3],
        latitude: latitude,
        longitude: longitude,
      );
      cities.add(city);
      keys.add([city.name, if (city.french != null) city.french!, if (city.arabic != null) city.arabic!]
          .map(foldPlaceName)
          .join('\n'));
    }
    return Cities._(List.unmodifiable(cities), List.unmodifiable(keys), Map.unmodifiable(countries));
  }

  /// The country's name in [languageCode] (English if it has no other);
  /// null for an unknown code.
  String? countryName(String? countryCode, String languageCode) {
    final names = _countries[countryCode];
    return names == null ? null : names[languageCode] ?? names['en'];
  }

  /// The towns whose name (in English, French or Arabic, accents and
  /// tashkeel aside) begins with [query], then those with a word that does,
  /// then those that contain it; the most populous first within each.
  List<City> search(String query, {int limit = 30}) {
    final needle = foldPlaceName(query);
    if (needle.isEmpty) return const [];
    final begins = <City>[], word = <City>[], contains = <City>[];
    for (var i = 0; i < _cities.length; i++) {
      final key = _keys[i];
      final at = key.indexOf(needle);
      if (at < 0) continue;
      if (key.startsWith(needle) || key.contains('\n$needle')) {
        begins.add(_cities[i]);
        if (begins.length >= limit) break;
      } else if (key.contains(' $needle')) {
        if (word.length < limit) word.add(_cities[i]);
      } else if (contains.length < limit) {
        contains.add(_cities[i]);
      }
    }
    return [...begins, ...word, ...contains].take(limit).toList();
  }

  /// The town nearest to a position; null only if the list is empty.
  City? nearest(double latitude, double longitude) {
    City? best;
    var bestDistance = double.infinity;
    // Degrees of longitude shrink with latitude; near enough for a ranking.
    final shrink = math.cos(latitude * math.pi / 180);
    for (final city in _cities) {
      final dLat = city.latitude - latitude;
      var dLon = (city.longitude - longitude).abs();
      if (dLon > 180) dLon = 360 - dLon;
      final d = dLat * dLat + dLon * shrink * dLon * shrink;
      if (d < bestDistance) {
        bestDistance = d;
        best = city;
      }
    }
    return best;
  }

  /// [city] as the place the user chose.
  Place chosen(City city) => Place(
        names: Map.unmodifiable(city.names),
        countryCode: city.countryCode,
        latitude: city.latitude,
        longitude: city.longitude,
        fromLocation: false,
      );

  /// A position the phone found, named after the nearest town. The position
  /// is kept to two decimals (about a kilometre): the prayer times need no
  /// more, and nothing finer is ever stored.
  Place located(double latitude, double longitude) {
    final lat = (latitude * 100).round() / 100, lon = (longitude * 100).round() / 100;
    final near = nearest(lat, lon);
    return Place(
      names: Map.unmodifiable(near?.names ?? {'en': '${lat.toStringAsFixed(2)}, ${lon.toStringAsFixed(2)}'}),
      countryCode: near?.countryCode,
      latitude: lat,
      longitude: lon,
      fromLocation: true,
    );
  }
}

/// [name] as search compares it: lower case, Latin accents and Arabic
/// tashkeel removed, the Arabic letters a keyboard confuses folded together,
/// hyphens and apostrophes dropped. "Saint-Étienne" is found by "saint
/// etienne", and "القاهرة" by "القاهره".
String foldPlaceName(String name) {
  final out = StringBuffer();
  var space = true; // no leading space, no double space
  for (final rune in name.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    // Apostrophes, tashkeel, and accents written as separate marks.
    if (_dropped.contains(ch) || _isMark(rune)) continue;
    final folded = _latin[ch] ?? letterMap[ch] ?? ch;
    if (folded == ' ' || folded == '-' || folded == '\t') {
      if (!space) out.write(' ');
      space = true;
    } else {
      out.write(folded);
      space = false;
    }
  }
  return out.toString().trimRight();
}

/// Apostrophes of every kind, and the Arabic tatweel.
const _dropped = {"'", '’', '‘', 'ʻ', 'ʼ', '`', 'ʿ', 'ʾ', 'ـ'};

/// Arabic harakat (U+064B..065F, U+0670), and Latin accents written as
/// separate marks (U+0300..036F).
bool _isMark(int rune) => (rune >= 0x64B && rune <= 0x65F) || rune == 0x670 || (rune >= 0x300 && rune <= 0x36F);

const _latin = <String, String>{
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a', //
  'ç': 'c', 'ć': 'c', 'č': 'c', 'ĉ': 'c',
  'ď': 'd', 'đ': 'd', 'ḍ': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
  'ğ': 'g', 'ġ': 'g',
  'ħ': 'h', 'ḥ': 'h',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ı': 'i', 'į': 'i',
  'ł': 'l', 'ľ': 'l', 'ļ': 'l',
  'ñ': 'n', 'ń': 'n', 'ň': 'n', 'ņ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o',
  'ř': 'r',
  'ś': 's', 'š': 's', 'ş': 's', 'ș': 's', 'ṣ': 's', 'ß': 'ss',
  'ť': 't', 'ţ': 't', 'ț': 't', 'ṭ': 't',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ź': 'z', 'ż': 'z', 'ž': 'z', 'ẓ': 'z',
  'æ': 'ae', 'œ': 'oe',
};
