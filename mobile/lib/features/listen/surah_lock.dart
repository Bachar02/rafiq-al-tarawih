import 'dart:math' as math;

import '../../core/recognition/models.dart';
import '../../data/quran.dart';

/// "Stay on this surah", following the imam.
///
/// A lock used to be the locked surah alone: once the imam recited on into
/// the next surah, everything he said was outside it, so recognition
/// discarded it and got lost (PLAN.md §36). Now a lock on a surah covers it
/// and the one after it, and moves on when the imam is confidently heard in
/// the next one. All of it is decided here, in the app; engines are only
/// given the range ([window]).
///
/// The lock moves only forward, one surah at a time, and only on committed
/// evidence: a preview, a miss, an unsure result or an unconfirmed far jump
/// never moves it, and nothing moves it back. The user can always move it by
/// hand ("the imam is here", "Stay on …", unlock).
abstract final class SurahLock {
  /// What an engine is told for [lock]: a surah and the one after it. Other
  /// locks (a juz) are used as they are.
  static Hint window(Hint lock) => switch (lock) {
        SurahHint(:final surah) => SurahRange(surah, math.min(surah + 1, Quran.surahCount)),
        _ => lock,
      };

  /// The lock after [heard], if it moves: on to the next surah once the imam
  /// is confidently heard reciting in it. Null: the lock stays as it is.
  static SurahHint? follow(Hint? lock, Heard heard) {
    if (lock is! SurahHint || !heard.isFinal) return null;
    final state = heard.state;
    // The ayah being recited, not `upcoming` (a prediction at the end of an
    // ayah) or `pending` (a far jump awaiting confirmation).
    final recited = state.position;
    if (state.status != TrackStatus.tracking || !state.evidence || recited == null) return null;
    return recited.surah == lock.surah + 1 ? SurahHint(recited.surah) : null;
  }

  /// The lock after the user says the imam is at [position]: his surah, unless
  /// it is the locked one or Al-Fatiha (recited at each rakʿah, always allowed).
  /// Null: the lock stays as it is.
  static SurahHint? correct(Hint? lock, Position position) {
    if (lock is! SurahHint || position.surah == lock.surah || position.surah == 1) return null;
    return SurahHint(position.surah);
  }
}
