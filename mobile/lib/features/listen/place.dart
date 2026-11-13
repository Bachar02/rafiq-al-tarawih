import '../../core/recognition/models.dart';
import 'surah_lock.dart';

/// Where the imam is, as far as the screen can honestly say (PLAN.md §38).
///
/// The engine's tie report (`TrackState.tied`, `tieTrusted`) says when words
/// fit several ayahs equally well. This turns it into one of four places, so
/// every widget agrees on what can be shown and offered:
///
/// * [Placed]: one ayah, confirmed or the last sure one held. The existing
///   reader and status line show it as they always have.
/// * [InSurah]: the surah is trusted, the ayah is not (the 31 copies of the
///   Ar-Rahman refrain).
/// * [AcrossSurahs]: two or three surahs remain, each with its copies.
/// * [Unplaced]: nothing trustworthy yet.
///
/// Conservative by construction: only a trusted tie gives a surah-level
/// place; a held position is kept, never replaced by a candidate; a lone
/// basmala or more than [maxSurahs] surahs offer nothing.
sealed class Place {
  const Place();

  /// The most surahs offered as choices: more is a list, not a choice.
  static const maxSurahs = 3;

  /// [state]'s place. [held] is the position on screen (confirmed or the last
  /// sure one); [status] the engine's verdict as the screen takes it (a miss
  /// keeps the last one with evidence); [live] whether a session is listening
  /// (a tie from a session that stopped is no longer news); [lock] the user's
  /// surah or juz lock.
  static Place resolve({
    required TrackState track,
    required TrackStatus status,
    required Position? held,
    required Hint? lock,
    required bool live,
  }) {
    final fallback = held != null ? Placed(held) : const Unplaced();
    // A confirmed position has no tie; several misses in a row (`lost`) make
    // it old news. A miss before any position (`idle`) holds it, like the
    // engine does.
    if (!live || status == TrackStatus.tracking || status == TrackStatus.lost) return fallback;
    if (!track.tieTrusted || track.tied.length < 2) return fallback;
    // The basmala (1:1) is recited before every surah but one: it says nothing
    // about where the imam is, whatever else it ties with (27:30).
    if (track.tied.any((p) => p.verseId == 1)) return fallback;
    final copies = _withinLock(track.tied, lock);
    if (copies.length < 2) return fallback;

    final bySurah = <int, List<Position>>{};
    for (final p in copies) {
      (bySurah[p.surah] ??= []).add(p);
    }
    // Al-Fatiha is never a surah to stay on: if its copies tie each other,
    // there is nothing safe to offer.
    if ((bySurah[1]?.length ?? 0) > 1) return fallback;
    if (bySurah.length == 1) {
      final surah = bySurah.keys.single;
      return InSurah(surah, List.unmodifiable(bySurah[surah]!), held);
    }
    if (bySurah.length > maxSurahs) return fallback;
    return AcrossSurahs(
      List.unmodifiable([for (final e in bySurah.entries) SurahChoice(e.key, List.unmodifiable(e.value))]),
      held,
    );
  }

  /// A lock set after the tie (a surah chosen from it) narrows it at once to
  /// what the engine now searches: the lock's window and Al-Fatiha. A subset
  /// of a complete tie is complete within it. A juz lock was already applied
  /// by the engine.
  static List<Position> _withinLock(List<Position> tied, Hint? lock) {
    if (lock == null) return tied;
    final window = SurahLock.window(lock);
    if (window is! SurahRange) return tied;
    return [
      for (final p in tied)
        if (p.surah == 1 || (window.first <= p.surah && p.surah <= window.last)) p
    ];
  }
}

/// One ayah: confirmed, or the last sure one held while the engine is unsure.
final class Placed extends Place {
  const Placed(this.position);

  final Position position;

  @override
  bool operator ==(Object other) => other is Placed && other.position == position;

  @override
  int get hashCode => position.hashCode;

  @override
  String toString() => 'Placed(${position.ref})';
}

/// The surah is trusted; the ayah is one of [copies] (Quran order, at least
/// two). [held] is the last sure position, kept on screen meanwhile.
final class InSurah extends Place {
  const InSurah(this.surah, this.copies, this.held);

  final int surah;
  final List<Position> copies;
  final Position? held;

  @override
  bool operator ==(Object other) =>
      other is InSurah && other.surah == surah && other.held == held && _same(other.copies, copies);

  @override
  int get hashCode => Object.hash(surah, held, Object.hashAll(copies));

  @override
  String toString() => 'InSurah($surah, ${copies.map((p) => p.ref)}, held: ${held?.ref})';
}

/// One candidate surah of an [AcrossSurahs] place, and its copies there.
final class SurahChoice {
  const SurahChoice(this.surah, this.copies);

  final int surah;
  final List<Position> copies;

  /// Its only copy, if it has one: that ayah can be chosen directly.
  Position? get only => copies.length == 1 ? copies.single : null;

  @override
  bool operator ==(Object other) => other is SurahChoice && other.surah == surah && _same(other.copies, copies);

  @override
  int get hashCode => Object.hash(surah, Object.hashAll(copies));

  @override
  String toString() => 'SurahChoice($surah, ${copies.map((p) => p.ref)})';
}

/// Two or three surahs fit equally well ([choices], Quran order). [held] is
/// the last sure position, kept on screen meanwhile.
final class AcrossSurahs extends Place {
  const AcrossSurahs(this.choices, this.held);

  final List<SurahChoice> choices;
  final Position? held;

  @override
  bool operator ==(Object other) => other is AcrossSurahs && other.held == held && _same(other.choices, choices);

  @override
  int get hashCode => Object.hash(held, Object.hashAll(choices));

  @override
  String toString() => 'AcrossSurahs($choices, held: ${held?.ref})';
}

/// Nothing trustworthy to show: the existing listening experience.
final class Unplaced extends Place {
  const Unplaced();

  @override
  bool operator ==(Object other) => other is Unplaced;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'Unplaced()';
}

bool _same<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
