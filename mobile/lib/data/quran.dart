/// The Quran text and structure, from the bundled `assets/quran/quran.json`.
///
/// That file is produced by `data/build_quran.py` (Tanzil Simple Clean text,
/// CC BY 3.0) and copied by `tool/sync_quran.py`; CI checks they match.
library;

import 'dart:convert';

class Surah {
  const Surah({
    required this.index,
    required this.nameAr,
    required this.nameTranslit,
    required this.nameEn,
    required this.ayahCount,
    required this.firstVerseId,
    required this.hasBasmala,
    this.basmalaUthmani = '',
    this.revelationType = '',
  });

  factory Surah.fromJson(Map<String, dynamic> j) => Surah(
        index: j['index'] as int,
        nameAr: j['name_ar'] as String,
        nameTranslit: j['name_translit'] as String,
        nameEn: j['name_en'] as String,
        ayahCount: j['ayah_count'] as int,
        firstVerseId: j['first_verse_id'] as int,
        hasBasmala: (j['has_basmala'] as bool?) ?? false,
        basmalaUthmani: (j['basmala_uthmani'] as String?) ?? '',
        revelationType: (j['revelation_type'] as String?) ?? '',
      );

  final int index;
  final String nameAr;
  final String nameTranslit;
  final String nameEn;
  final int ayahCount;
  final int firstVerseId;

  /// The basmala is recited before ayah 1 (it is not part of it). False for 1 and 9.
  final bool hasBasmala;

  /// This surah's basmala as printed (95 and 97 differ slightly). Empty if none.
  final String basmalaUthmani;

  /// "Meccan" or "Medinan".
  final String revelationType;

  int get lastVerseId => firstVerseId + ayahCount - 1;
}

class Verse {
  const Verse({required this.id, required this.surah, required this.ayah, required this.text, String? uthmani})
      : uthmani = uthmani ?? text;

  final int id;
  final int surah;
  final int ayah;

  /// Simple Clean (no diacritics): what matching uses.
  final String text;

  /// Uthmani script with full tashkeel: what the reader shows.
  final String uthmani;
}

/// An ordered partition of the Quran's verses into numbered divisions (juz,
/// Madinah-mushaf pages, hizb quarters), each given by its first verse id.
///
/// Lookups are binary searches: called per ayah while scrolling, they must
/// not scan 604 pages.
class Divisions {
  Divisions._(this.name, this._starts);

  /// Builds from ordered `{surah, ayah}` marks. Throws [FormatException] if
  /// they are not a partition: [expected] marks, the first at 1:1, each after
  /// the previous one and inside its surah.
  factory Divisions._fromMarks(String name, List<dynamic> marks, List<Surah> surahs, int expected) {
    if (marks.length != expected) {
      throw FormatException('quran.json has ${marks.length} $name marks, expected $expected');
    }
    final starts = <int>[];
    for (final m in marks.cast<Map<String, dynamic>>()) {
      final surahIndex = m['surah'] as int, ayah = m['ayah'] as int;
      if (surahIndex < 1 || surahIndex > surahs.length) throw FormatException('$name mark in surah $surahIndex');
      final surah = surahs[surahIndex - 1];
      if (ayah < 1 || ayah > surah.ayahCount) throw FormatException('$name mark at $surahIndex:$ayah');
      final id = surah.firstVerseId + ayah - 1;
      if (starts.isEmpty ? id != 1 : id <= starts.last) {
        throw FormatException('$name ${starts.length + 1} ($surahIndex:$ayah) is out of order');
      }
      starts.add(id);
    }
    return Divisions._(name, List.unmodifiable(starts));
  }

  /// "juz", "page" or "hizb quarter": for messages only.
  final String name;
  final List<int> _starts;

  int get count => _starts.length;

  /// The first verse id of division [index] (1-based).
  int start(int index) => _starts[index - 1];

  /// The last verse id of division [index] (1-based).
  int end(int index) => index == count ? Quran.verseCount : _starts[index] - 1;

  /// The division (1-based) that [verseId] falls in.
  int of(int verseId) {
    var lo = 0, hi = _starts.length; // first start > verseId
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_starts[mid] <= verseId) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < 1 ? 1 : lo;
  }

  /// [verseId] is the first verse of a division.
  bool isStart(int verseId) => _starts[of(verseId) - 1] == verseId;
}

class Quran {
  Quran._(this.surahs, this.verses, this.juzs, this.pages, this.quarters);

  static const verseCount = 6236;
  static const surahCount = 114;
  static const pageCount = 604;

  /// Parse the bundled JSON. Throws [FormatException] if it is not a complete Quran.
  factory Quran.fromJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final surahs = [for (final s in json['surahs'] as List) Surah.fromJson(s as Map<String, dynamic>)];
    final verses = [
      for (final v in (json['verses'] as List).cast<Map<String, dynamic>>())
        Verse(
          id: v['id'] as int,
          surah: v['surah'] as int,
          ayah: v['ayah'] as int,
          text: v['text'] as String,
          uthmani: v['text_uthmani'] as String?,
        ),
    ];
    if (surahs.length != surahCount || verses.length != verseCount) {
      throw FormatException('quran.json is incomplete: ${surahs.length} surahs, ${verses.length} verses');
    }
    List<dynamic> marks(String key) =>
        json[key] as List<dynamic>? ?? (throw FormatException('quran.json has no "$key"; rebuild it'));
    return Quran._(
      List.unmodifiable(surahs),
      List.unmodifiable(verses),
      Divisions._fromMarks('juz', marks('juzs'), surahs, 30),
      Divisions._fromMarks('page', marks('pages'), surahs, 604),
      Divisions._fromMarks('hizb quarter', marks('hizb_quarters'), surahs, 240),
    );
  }

  final List<Surah> surahs;
  final List<Verse> verses;

  /// The 30 ajzāʾ.
  final Divisions juzs;

  /// The 604 pages of the Madinah mushaf (Tanzil's page marks). Only where
  /// each page starts: the app's text flows, it is not a page facsimile.
  final Divisions pages;

  /// The 240 hizb quarters (rubʿ al-ḥizb), 8 per juz.
  final Divisions quarters;

  Surah surah(int index) => surahs[index - 1];

  Verse verse(int id) => verses[id - 1];

  /// The verse id of [surah]:[ayah], or null if there is no such ayah.
  int? verseId(int surah, int ayah) {
    if (surah < 1 || surah > surahs.length) return null;
    final s = surahs[surah - 1];
    if (ayah < 1 || ayah > s.ayahCount) return null;
    return s.firstVerseId + ayah - 1;
  }

  List<Verse> surahVerses(int index) {
    final s = surah(index);
    return verses.sublist(s.firstVerseId - 1, s.lastVerseId);
  }

  int get juzCount => juzs.count;

  /// Which juz (1-based) a verse falls in.
  int juzOf(int verseId) => juzs.of(verseId);

  /// Which Madinah-mushaf page (1-based) a verse starts on.
  int pageOf(int verseId) => pages.of(verseId);

  /// The surah a juz begins in (for labelling the juz picker).
  Surah juzStartSurah(int juz) => surah(verse(juzs.start(juz)).surah);
}
