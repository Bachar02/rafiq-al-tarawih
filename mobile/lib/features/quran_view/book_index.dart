/// The Quran as one list: each surah's header, then its ayahs.
///
/// Item index space (0-based): surah 1's header, 1:1 .. 1:7, surah 2's
/// header, 2:1, … 114:6. That is 6,236 ayahs + 114 headers = 6,350 items.
/// Pure arithmetic over the [Quran]; no Flutter.
library;

import '../../data/quran.dart';

/// One row of the Book.
sealed class BookItem {
  const BookItem();
}

/// A surah's title and, for surahs other than 1 and 9, its basmala.
final class SurahHeaderItem extends BookItem {
  const SurahHeaderItem(this.surah);
  final Surah surah;
}

/// One ayah.
final class AyahItem extends BookItem {
  const AyahItem(this.verse);
  final Verse verse;
}

class BookIndex {
  BookIndex(this.quran)
      : _headers = List.unmodifiable([for (final s in quran.surahs) s.firstVerseId - 1 + s.index - 1]);

  final Quran quran;

  /// Item index of each surah's header, ascending.
  final List<int> _headers;

  int get length => Quran.verseCount + Quran.surahCount;

  /// The item index of verse [verseId]: its surah's header comes before it,
  /// as do the headers of every earlier surah.
  int ofVerse(int verseId) => verseId - 1 + quran.verse(verseId).surah;

  /// The item index of surah [surah]'s header.
  int ofSurah(int surah) => _headers[surah - 1];

  /// The surah (1-based) item [index] belongs to.
  int surahAt(int index) {
    var lo = 0, hi = _headers.length; // first header > index
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_headers[mid] <= index) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  BookItem at(int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    final surah = surahAt(index);
    if (_headers[surah - 1] == index) return SurahHeaderItem(quran.surah(surah));
    return AyahItem(quran.verse(index + 1 - surah));
  }

  /// The verse an item stands for: an ayah itself, a header its surah's 1st ayah.
  int verseAt(int index) => switch (at(index)) {
        AyahItem(:final verse) => verse.id,
        SurahHeaderItem(:final surah) => surah.firstVerseId,
      };
}
