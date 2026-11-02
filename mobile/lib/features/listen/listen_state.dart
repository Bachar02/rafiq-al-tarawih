import '../../core/recognition/models.dart';

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

enum ListenError { micPermission, unreachable, server, microphone }

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
      );
}

const _keep = Object();
