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

class Quran {
  Quran._(this.surahs, this.verses, this._juzStarts);

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
    if (surahs.length != 114 || verses.length != 6236) {
      throw FormatException('quran.json is incomplete: ${surahs.length} surahs, ${verses.length} verses');
    }
    final juzStarts = <int>[];
    for (final j in json['juzs'] as List) {
      final m = j as Map<String, dynamic>;
      final surah = surahs[(m['surah'] as int) - 1];
      juzStarts.add(surah.firstVerseId + (m['ayah'] as int) - 1);
    }
    return Quran._(surahs, verses, juzStarts);
  }

  final List<Surah> surahs;
  final List<Verse> verses;
  final List<int> _juzStarts; // first verse id of each juz

  Surah surah(int index) => surahs[index - 1];

  Verse verse(int id) => verses[id - 1];

  List<Verse> surahVerses(int index) {
    final s = surah(index);
    return verses.sublist(s.firstVerseId - 1, s.lastVerseId);
  }

  int get juzCount => _juzStarts.length;

  /// Which juz (1-based) a verse falls in.
  int juzOf(int verseId) {
    var juz = 1;
    for (var i = 0; i < _juzStarts.length; i++) {
      if (_juzStarts[i] <= verseId) juz = i + 1;
    }
    return juz;
  }

  /// The surah a juz begins in (for labelling the juz picker).
  Surah juzStartSurah(int juz) => surah(verse(_juzStarts[juz - 1]).surah);
}
