/// The adhkar: the remembrances of the morning and the evening, after the
/// prayer, before sleep, and short ones for any time, from the bundled
/// `assets/adhkar/adhkar.json`.
///
/// The Arabic follows Ḥiṣn al-Muslim (Saʿīd al-Qaḥṭānī), each dhikr with the
/// collections of hadith that report it. Quranic passages (Āyat al-Kursī,
/// the last three surahs, the end of al-Baqarah) are not copied: they are
/// references, shown from the app's own Quran text. The English and French
/// meanings are Rafiq's (assets/adhkar/NOTICE.txt).
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'khatm.dart' show dateOnly, parseDayKey;
import 'quran.dart';
import 'reading_store.dart' show ReadingLog;

/// The five collections, in the order the Adhkar screen lists them.
enum AdhkarCollection { morning, evening, prayer, sleep, anytime }

/// A run of ayahs: a whole surah, or [from]..[to] of it.
class QuranPassage {
  const QuranPassage({required this.surah, required this.from, required this.to, required this.wholeSurah});

  final int surah;
  final int from;
  final int to;

  /// The whole surah: shown with its basmala (if it has one).
  final bool wholeSurah;

  /// `112` (a whole surah), `2:255` or `2:285-286`. Throws [FormatException]
  /// if the surah or the ayahs do not exist.
  factory QuranPassage.parse(String ref, Quran quran) {
    final m = RegExp(r'^(\d+)(?::(\d+)(?:-(\d+))?)?$').firstMatch(ref);
    if (m == null) throw FormatException('adhkar: bad Quran reference "$ref"');
    final surah = int.parse(m[1]!);
    if (surah < 1 || surah > quran.surahs.length) throw FormatException('adhkar: no surah $surah');
    final whole = m[2] == null;
    final from = whole ? 1 : int.parse(m[2]!);
    final to = whole ? quran.surah(surah).ayahCount : int.parse(m[3] ?? m[2]!);
    if (quran.verseId(surah, from) == null || quran.verseId(surah, to) == null || to < from) {
      throw FormatException('adhkar: no ayahs $ref');
    }
    return QuranPassage(surah: surah, from: from, to: to, wholeSurah: whole);
  }

  /// The ayahs, from the app's Quran text.
  List<Verse> verses(Quran quran) => [for (var a = from; a <= to; a++) quran.verse(quran.verseId(surah, a)!)];
}

/// One dhikr, as said in one collection: its Arabic (if not only Quran), the
/// Quran it recites, how many times, and where it is reported.
class Dhikr {
  const Dhikr({
    required this.id,
    required this.arabic,
    required this.passages,
    required this.count,
    required this.notes,
    required this.meanings,
    required this.sources,
    this.transliterations = const {},
  });

  /// Unique within its collection; the morning and evening share theirs.
  final String id;

  /// The words said, or null for a dhikr that is only Quran.
  final String? arabic;

  /// The Quran recited after [arabic], in order.
  final List<QuranPassage> passages;

  /// How many times it is said (1 or more).
  final int count;

  /// How or when to say it, by language (`en`, `fr`, `ar`).
  final Map<String, String> notes;

  /// The meaning of [arabic] in English and French (not of the Quran: that
  /// is the translation's job).
  final Map<String, String> meanings;

  /// Who reports it: keys of [Adhkar.sourceNames], e.g. `bukhari`.
  final List<String> sources;

  /// How [arabic] is said, in Latin letters, by language (`en`, `fr`): for
  /// someone who cannot read the Arabic script.
  final Map<String, String> transliterations;

  String? note(String languageCode) => notes[languageCode] ?? notes['en'];

  /// Null in Arabic (the words are the text) and for Quran-only adhkar.
  String? meaning(String languageCode) => languageCode == 'ar' ? null : meanings[languageCode] ?? meanings['en'];

  /// [arabic] in Latin letters, the way [languageCode] spells sounds. Null
  /// in Arabic (the words are the text) and where there is none.
  String? transliteration(String languageCode) =>
      languageCode == 'ar' ? null : transliterations[languageCode] ?? transliterations['en'];

  /// Short enough to stand alone in a notification: words, no Quran.
  bool get standsAlone => arabic != null && passages.isEmpty;

  /// Parses and checks one dhikr (or dua) of [file]: something to say, a
  /// count of at least 1, known [sources], real ayahs. [variant] gives other
  /// words for the same dhikr (the evening's). Throws [FormatException].
  factory Dhikr.fromJson(
    Map<String, dynamic> j, {
    required Quran quran,
    required Map<String, Map<String, String>> sources,
    required String file,
    Map<String, dynamic>? variant,
  }) {
    final id = j['id'];
    if (id is! String || id.isEmpty) throw FormatException('$file: an item has no id');
    final arabic = (variant?['ar'] ?? j['ar']) as String?;
    final passages = [
      for (final r in (j['quran'] as List<dynamic>? ?? const [])) QuranPassage.parse(r as String, quran)
    ];
    final count = j['count'] as int? ?? 1;
    final keys = (j['source'] as List<dynamic>? ?? const []).cast<String>();
    if (arabic == null && passages.isEmpty) throw FormatException('$file: $id says nothing');
    if (count < 1) throw FormatException('$file: $id is said $count times');
    if (keys.isEmpty) throw FormatException('$file: $id has no source');
    for (final k in keys) {
      if (!sources.containsKey(k)) throw FormatException('$file: $id has an unknown source "$k"');
    }
    return Dhikr(
      id: id,
      arabic: arabic,
      passages: List.unmodifiable(passages),
      count: count,
      notes: _texts(j['note']),
      meanings: _texts(variant?['meaning'] ?? j['meaning']),
      sources: List.unmodifiable(keys),
      // Evening words of their own have their own: the morning's would not match.
      transliterations: _texts(variant?['ar'] != null ? variant!['translit'] : j['translit']),
    );
  }

  static Map<String, String> _texts(Object? j) =>
      j == null ? const {} : (j as Map<String, dynamic>).cast<String, String>();
}

/// The names of the collections of hadith (and the Quran) that report the
/// adhkar and duas, by key and language.
Map<String, Map<String, String>> parseSourceNames(Object? json, String file) {
  if (json is! Map<String, dynamic>) throw FormatException('$file: no sources');
  return {
    for (final e in json.entries) e.key: (e.value as Map<String, dynamic>).cast<String, String>(),
  };
}

/// Each of [keys] by name in [languageCode] (else English, else the key).
List<String> sourceNamesOf(Map<String, Map<String, String>> names, List<String> keys, String languageCode) => [
      for (final key in keys) names[key]?[languageCode] ?? names[key]?['en'] ?? key,
    ];

/// The bundled adhkar.
class Adhkar {
  Adhkar._(this._collections, this.sourceNames);

  /// No adhkar (a build without the file): the screen says nothing is there.
  static final empty = Adhkar._({for (final c in AdhkarCollection.values) c: const <Dhikr>[]}, const {});

  final Map<AdhkarCollection, List<Dhikr>> _collections;

  /// Each source's name by language: `{bukhari: {en: al-Bukhari, ...}}`.
  final Map<String, Map<String, String>> sourceNames;

  List<Dhikr> of(AdhkarCollection collection) => _collections[collection]!;

  /// What the dhikr reminders pick from: the short adhkar for any time.
  List<Dhikr> get forNotifications => [
        for (final d in of(AdhkarCollection.anytime))
          if (d.standsAlone) d
      ];

  /// The sources of [dhikr] by name, in [languageCode].
  List<String> sourcesOf(Dhikr dhikr, String languageCode) => sourceNamesOf(sourceNames, dhikr.sources, languageCode);

  /// Parses and checks the file: every collection present, ids unique, a
  /// count of at least 1, something to say, known sources, real ayahs.
  /// Throws [FormatException] otherwise: a broken file must fail the build's
  /// tests, not show a half-empty screen.
  factory Adhkar.fromJson(String raw, Quran quran) {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic> || json['v'] != 1) throw const FormatException('adhkar.json: not version 1');
    final sources = parseSourceNames(json['sources'], 'adhkar.json');
    final collectionsJson = json['collections'] as Map<String, dynamic>;

    List<Map<String, dynamic>> list(String key) {
      final items = collectionsJson[key];
      if (items is! List || items.isEmpty) throw FormatException('adhkar.json: no "$key" collection');
      return items.cast<Map<String, dynamic>>();
    }

    Dhikr parse(Map<String, dynamic> j, {Map<String, dynamic>? variant}) =>
        Dhikr.fromJson(j, quran: quran, sources: sources, file: 'adhkar.json', variant: variant);

    // The morning and the evening share one list: the evening says its own
    // words where they differ (أمسينا for أصبحنا), and some are for only one.
    final both = list('morning_evening');
    final collections = <AdhkarCollection, List<Dhikr>>{
      AdhkarCollection.morning: [
        for (final j in both)
          if (j['only'] != 'evening') parse(j),
      ],
      AdhkarCollection.evening: [
        for (final j in both)
          if (j['only'] != 'morning') parse(j, variant: j['evening'] as Map<String, dynamic>?),
      ],
      AdhkarCollection.prayer: [for (final j in list('prayer')) parse(j)],
      AdhkarCollection.sleep: [for (final j in list('sleep')) parse(j)],
      AdhkarCollection.anytime: [for (final j in list('anytime')) parse(j)],
    };
    for (final MapEntry(key: c, value: items) in collections.entries) {
      final ids = items.map((d) => d.id).toSet();
      if (ids.length != items.length) throw FormatException('adhkar.json: an id is repeated in ${c.name}');
    }
    return Adhkar._(
      {for (final e in collections.entries) e.key: List.unmodifiable(e.value)},
      Map.unmodifiable(sources),
    );
  }
}

/// Today's counts: how many times each dhikr has been said, by collection.
/// A new day starts from zero.
class AdhkarDay {
  AdhkarDay(DateTime day, [Map<String, int> counts = const {}])
      : day = dateOnly(day),
        _counts = Map.unmodifiable(counts);

  final DateTime day;
  final Map<String, int> _counts;

  static String _key(AdhkarCollection c, String id) => '${c.name}/$id';

  int countOf(AdhkarCollection c, Dhikr d) => (_counts[_key(c, d.id)] ?? 0).clamp(0, d.count);

  bool isDone(AdhkarCollection c, Dhikr d) => countOf(c, d) >= d.count;

  /// How many of [items] are done.
  int doneIn(AdhkarCollection c, List<Dhikr> items) => items.where((d) => isDone(c, d)).length;

  /// One more time said (never past its count).
  AdhkarDay counted(AdhkarCollection c, Dhikr d) =>
      AdhkarDay(day, {..._counts, _key(c, d.id): (countOf(c, d) + 1).clamp(0, d.count)});

  /// [c] from the start again.
  AdhkarDay reset(AdhkarCollection c) => AdhkarDay(day, {
        for (final e in _counts.entries)
          if (!e.key.startsWith('${c.name}/')) e.key: e.value
      });

  Map<String, Object> toJson() => {'v': 1, 'day': ReadingLog.dayKey(day), 'counts': _counts};

  /// Null if [json] is not a day of counts.
  static AdhkarDay? fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return null;
    final day = parseDayKey(json['day']);
    final counts = json['counts'];
    if (day == null || counts is! Map) return null;
    return AdhkarDay(day, {
      for (final e in counts.entries)
        if (e.key is String && e.value is int) e.key as String: e.value as int,
    });
  }
}

/// Keeps today's counts on the phone. Losing them is harmless (they are one
/// day's ticks), so an unreadable record is simply started again.
class AdhkarStore {
  AdhkarStore(this._prefs);

  final SharedPreferences _prefs;

  static const key = 'adhkar_day.v1';

  AdhkarDay? load() {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return AdhkarDay.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<bool> save(AdhkarDay day) => _prefs.setString(key, jsonEncode(day.toJson()));
}
