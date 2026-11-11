/// What the recognition engine reports, independent of how it is produced
/// (on the phone, or on the development server).
library;

/// The tracker's verdict on the latest audio.
enum TrackStatus {
  /// Nothing has been recognised yet.
  idle,

  /// Confidently following the imam.
  tracking,

  /// Showing the last good position but not sure (noise, ambiguous text).
  uncertain,

  /// Several chunks in a row could not be matched.
  lost;

  static TrackStatus parse(String? value) => switch (value) {
        'tracking' => TrackStatus.tracking,
        'uncertain' => TrackStatus.uncertain,
        'lost' => TrackStatus.lost,
        _ => TrackStatus.idle,
      };
}

/// A place in the Quran. `verseId` is the global index, 1 (1:1) .. 6236 (114:6).
class Position {
  const Position({required this.verseId, required this.surah, required this.ayah});

  final int verseId;
  final int surah;
  final int ayah;

  String get ref => '$surah:$ayah';

  @override
  bool operator ==(Object other) => other is Position && other.verseId == verseId;

  @override
  int get hashCode => verseId.hashCode;

  @override
  String toString() => 'Position($ref)';
}

/// Where the app thinks the imam is, after one chunk of audio.
class TrackState {
  const TrackState({
    required this.status,
    this.position,
    this.confidence = 0,
    this.pending,
    this.alternatives = const [],
    this.upcoming,
  });

  static const empty = TrackState(status: TrackStatus.idle);

  /// The ayah being recited (null until detected).
  final Position? position;
  final TrackStatus status;

  /// 0..1, how sure the tracker is about [position].
  final double confidence;

  /// A first guess or a far jump awaiting confirmation. Never shown as fact.
  final Position? pending;

  /// Other plausible positions when the recited text is ambiguous.
  final List<Position> alternatives;

  /// Set when [position] was recited to its end: the ayah the imam goes to next.
  final Position? upcoming;

  /// The ayah a follow-along screen should highlight now.
  Position? get showing => upcoming ?? position;
}

/// Optional user help. Detection works without it.
sealed class Hint {
  const Hint();
}

class SurahHint extends Hint {
  const SurahHint(this.surah);
  final int surah;

  @override
  bool operator ==(Object other) => other is SurahHint && other.surah == surah;

  @override
  int get hashCode => surah.hashCode;
}

class JuzHint extends Hint {
  const JuzHint(this.juz);
  final int juz;

  @override
  bool operator ==(Object other) => other is JuzHint && other.juz == juz;

  @override
  int get hashCode => juz.hashCode;
}

/// Everything a recognition engine can tell the app.
sealed class RecognitionEvent {
  const RecognitionEvent();
}

/// The engine is ready for audio (the speech model is loaded).
class EngineReady extends RecognitionEvent {
  const EngineReady({this.device});

  /// Where the speech model runs, e.g. "cuda" or "cpu", if known.
  final String? device;
}

/// One recognised stretch of audio and the resulting position.
class Heard extends RecognitionEvent {
  const Heard({
    required this.text,
    required this.start,
    required this.end,
    required this.asrMs,
    required this.state,
    required this.isFinal,
  });

  /// What the speech model heard (with diacritics).
  final String text;

  /// Seconds since listening started.
  final double start;
  final double end;
  final int asrMs;
  final TrackState state;

  /// False for a live preview of a chunk the imam is still reciting.
  final bool isFinal;
}

/// Something was skipped; the session continues.
class EngineWarning extends RecognitionEvent {
  const EngineWarning(this.message) : skippedSeconds = null;

  /// Recognition fell behind and dropped this much old audio, to follow the
  /// imam now (the app says it in the interface language).
  const EngineWarning.fellBehind(double this.skippedSeconds) : message = '';

  /// The engine's own words (the server's), when not [skippedSeconds].
  final String message;
  final double? skippedSeconds;
}

/// Unrecoverable: the session is over.
class EngineFailure extends RecognitionEvent {
  const EngineFailure(this.message, {this.kind = FailureKind.server});
  final String message;
  final FailureKind kind;
}

enum FailureKind {
  /// The server could not be reached at all.
  unreachable,

  /// The server reported an error (model failed, bad request...).
  server,

  /// The speech model on the phone could not be prepared or run.
  model,

  /// The app was built without its speech model.
  missingModel,
}

/// The connection dropped and the engine is retrying. Audio keeps flowing.
class EngineReconnecting extends RecognitionEvent {
  const EngineReconnecting({required this.attempt, required this.delay});
  final int attempt;
  final Duration delay;
}

/// The engine finished after a graceful stop.
class EngineDone extends RecognitionEvent {
  const EngineDone();
}
