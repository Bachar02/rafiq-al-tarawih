import '../../core/recognition/models.dart';
import 'place.dart';

export 'place.dart';

/// Where the listening session is in its lifecycle.
enum SessionPhase {
  /// Not listening. The last position (if any) stays visible.
  idle,

  /// Asking for the mic, connecting, or waiting for the speech model.
  connecting,

  /// Audio is flowing and results are arriving.
  listening,

  /// The connection dropped; the mic keeps running while we reconnect.
  reconnecting,

  /// Finishing the last chunk after the user pressed stop.
  stopping,

  /// Stopped because the app went to the background.
  paused,

  /// Stopped by an error the user must act on (see [ListenError]).
  failed,
}

enum ListenError { micPermission, unreachable, server, microphone, model, missingModel }

/// One line of the diagnostics transcript.
class TranscriptLine {
  const TranscriptLine({
    required this.text,
    required this.start,
    required this.end,
    required this.asrMs,
    required this.shown,
    required this.isFinal,
  });

  final String text;
  final double start;
  final double end;
  final int asrMs;
  final Position? shown;
  final bool isFinal;
}

/// The word the engine last said is being recited (word highlighting, a
/// developer setting), and when the audio behind it was heard.
class LiveWord {
  const LiveWord(this.word, this.heardAt);

  final HeardWord word;

  /// About when that audio ended: the result's arrival minus its
  /// transcription time. The highlight goes once this is too old.
  final DateTime heardAt;
}

class ListenState {
  const ListenState({
    this.phase = SessionPhase.idle,
    this.track = TrackState.empty,
    this.hint,
    this.level = 0,
    this.device,
    this.warning,
    this.error,
    this.errorMessage,
    this.reconnectAttempt = 0,
    this.transcript = const [],
    this.livePartial,
    this.startedAt,
    this.detectedAfter,
    this.lock,
    this.readerSurah,
    this.browsing = false,
    this.readerOnTie = false,
    this.anchor,
    this.lastSure,
    this.confirmedAt,
    this.lastSoundAt,
    this.liveWord,
    this.evidenceStatus,
  });

  final SessionPhase phase;

  /// The latest tracker verdict (kept after stopping, so the screen does not go blank).
  final TrackState track;

  /// Optional "tonight is surah X / juz N" help, applied when listening starts.
  final Hint? hint;

  /// Current microphone level, 0..1.
  final double level;

  /// Where the speech model runs ("cuda", "cpu"), once known.
  final String? device;

  /// A transient notice from the server (e.g. it fell behind and skipped audio).
  final String? warning;

  final ListenError? error;
  final String? errorMessage;
  final int reconnectAttempt;

  /// Final transcripts, newest last (diagnostics only).
  final List<TranscriptLine> transcript;

  /// The live preview of the chunk being recited, if any.
  final TranscriptLine? livePartial;

  final DateTime? startedAt;

  /// How long after starting the first position appeared.
  final Duration? detectedAfter;

  /// The user locked recognition to this surah/juz ("this is the right surah").
  final Hint? lock;

  /// The surah the reader shows. Changes only on a confident result, a user
  /// correction, or browsing, so an unsure guess never yanks the text away.
  final int? readerSurah;

  /// The user navigated to a surah themselves; following is paused until
  /// they choose "Follow the imam".
  final bool browsing;

  /// [readerSurah] was opened by repeated words in a trusted surah, before any
  /// position: another trusted surah may replace it, and the first position
  /// does. False once a position, the user or a lock opened it.
  final bool readerOnTie;

  /// The imam's main position: the last confirmed one outside Al-Fatiha.
  /// Kept while Al-Fatiha is recited at each rakʿah, so the screen stays on
  /// the imam's surah.
  final Position? anchor;

  /// The last position the engine confirmed (`tracking`) or the user set.
  /// Held while the engine is unsure: the number on screen never changes to
  /// an unconfirmed one.
  final Position? lastSure;

  /// When the engine last reported `tracking` (or the user corrected the
  /// position): the freshness behind a filled position marker.
  final DateTime? confirmedAt;

  /// When the microphone level was last at or above [quietLevel].
  final DateTime? lastSoundAt;

  /// The word being recited, while the engine is sure of it and the evidence
  /// is fresh (word highlighting only; otherwise always null).
  final LiveWord? liveWord;

  /// The engine's status on its latest result with evidence (this session,
  /// or a user correction).
  final TrackStatus? evidenceStatus;

  /// The engine's verdict, as the screen should take it. A miss (audio that
  /// matched no Quran: a breath's first word, "āmīn", silence) is no news, not
  /// doubt: the last verdict with evidence stands. Genuine doubt (rivals, an
  /// unconfirmed far jump, an exact tie) is evidence, so it still shows. So
  /// is `lost`: several misses in a row are something to say.
  TrackStatus get trackStatus =>
      !track.evidence && track.status == TrackStatus.uncertain ? evidenceStatus ?? track.status : track.status;

  /// The engine's position when it is sure; otherwise the last sure one.
  Position? get _sure => trackStatus == TrackStatus.tracking || lastSure == null ? track.showing : lastSure;

  /// Al-Fatiha is being recited inside another surah's session.
  bool get inFatihaExcursion {
    final shown = _sure, main = anchor;
    return shown != null && shown.surah == 1 && main != null && main.surah != 1;
  }

  /// The position the header and the Quran column show: the engine's sure
  /// position, except during Al-Fatiha, when the imam's main surah and last
  /// ayah stay.
  Position? get displayed => inFatihaExcursion ? anchor : _sure;

  /// Where the imam is, as far as the screen can honestly say: one ayah, a
  /// trusted surah whose ayah repeats, two or three surahs, or nowhere yet
  /// ([Place]). The position on screen is always kept as held.
  Place get place => Place.resolve(
        track: track,
        status: trackStatus,
        held: displayed,
        lock: lock,
        live: phase == SessionPhase.listening,
      );

  bool get isActive => switch (phase) {
        SessionPhase.connecting || SessionPhase.listening || SessionPhase.reconnecting || SessionPhase.stopping => true,
        _ => false,
      };

  ListenState copyWith({
    SessionPhase? phase,
    TrackState? track,
    Object? hint = _keep,
    double? level,
    Object? device = _keep,
    Object? warning = _keep,
    Object? error = _keep,
    Object? errorMessage = _keep,
    int? reconnectAttempt,
    List<TranscriptLine>? transcript,
    Object? livePartial = _keep,
    Object? startedAt = _keep,
    Object? detectedAfter = _keep,
    Object? lock = _keep,
    Object? readerSurah = _keep,
    bool? browsing,
    bool? readerOnTie,
    Object? anchor = _keep,
    Object? lastSure = _keep,
    Object? confirmedAt = _keep,
    Object? lastSoundAt = _keep,
    Object? liveWord = _keep,
    Object? evidenceStatus = _keep,
  }) =>
      ListenState(
        phase: phase ?? this.phase,
        track: track ?? this.track,
        hint: identical(hint, _keep) ? this.hint : hint as Hint?,
        level: level ?? this.level,
        device: identical(device, _keep) ? this.device : device as String?,
        warning: identical(warning, _keep) ? this.warning : warning as String?,
        error: identical(error, _keep) ? this.error : error as ListenError?,
        errorMessage: identical(errorMessage, _keep) ? this.errorMessage : errorMessage as String?,
        reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
        transcript: transcript ?? this.transcript,
        livePartial: identical(livePartial, _keep) ? this.livePartial : livePartial as TranscriptLine?,
        startedAt: identical(startedAt, _keep) ? this.startedAt : startedAt as DateTime?,
        detectedAfter: identical(detectedAfter, _keep) ? this.detectedAfter : detectedAfter as Duration?,
        lock: identical(lock, _keep) ? this.lock : lock as Hint?,
        readerSurah: identical(readerSurah, _keep) ? this.readerSurah : readerSurah as int?,
        browsing: browsing ?? this.browsing,
        readerOnTie: readerOnTie ?? this.readerOnTie,
        anchor: identical(anchor, _keep) ? this.anchor : anchor as Position?,
        lastSure: identical(lastSure, _keep) ? this.lastSure : lastSure as Position?,
        confirmedAt: identical(confirmedAt, _keep) ? this.confirmedAt : confirmedAt as DateTime?,
        lastSoundAt: identical(lastSoundAt, _keep) ? this.lastSoundAt : lastSoundAt as DateTime?,
        liveWord: identical(liveWord, _keep) ? this.liveWord : liveWord as LiveWord?,
        evidenceStatus: identical(evidenceStatus, _keep) ? this.evidenceStatus : evidenceStatus as TrackStatus?,
      );
}

const _keep = Object();

/// Microphone peak level below which the room counts as quiet ("Little
/// sound"). An uncalibrated starting value: calibrate on real Taraweeh
/// recordings (hall noise floors) before release.
const quietLevel = 0.03;

/// How long without sound, or without a confirmed update, before the screen
/// says so. A starting value, like [quietLevel]: calibrate on rukūʿ and sujūd
/// lengths in real recordings.
const inferredStateAfter = Duration(seconds: 10);
