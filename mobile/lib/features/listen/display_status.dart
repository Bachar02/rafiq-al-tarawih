import '../../core/recognition/models.dart';
import 'listen_state.dart';
import '../../l10n/l10n.dart';

/// How the position marker is drawn (brand book §7).
enum MarkerFill {
  /// No trustworthy position (none yet, paused, error): no marker at all.
  none,

  /// The engine reports `tracking` and confirmed the position within
  /// [inferredStateAfter].
  filled,

  /// A position is held without fresh confirmation, for any reason.
  hollow,
}

/// What the screen says about recognition, derived from session phase,
/// tracker status and two app-inferred observations, in one place, so every
/// widget agrees.
///
/// It says only what the engine knows plus what the phone measured. The
/// inferred states ([littleSound], [noNewMatch]) describe the measurement,
/// never its cause, and never predict what happens next. Unconfirmed
/// (`pending`) positions are never shown.
enum DisplayStatus {
  /// Not listening, nothing to show yet.
  ready,

  /// Not listening; the last position stays on screen.
  stopped,
  connecting,

  /// Listening, no position yet.
  listening,
  following,

  /// Al-Fatiha inside another surah's session; the imam's surah stays.
  fatiha,

  /// App-inferred: sound is coming in, but no confirmed update for a while.
  noNewMatch,

  /// App-inferred: the microphone has picked up very little for a while.
  littleSound,

  /// Engine `uncertain`.
  notSure,

  /// Engine `lost`: several chunks in a row matched no Quran.
  notMatching,

  /// Server build only.
  reconnecting,
  stopping,

  /// The app went to the background (see the Notice).
  paused,

  /// Stopped by an error (see the Notice).
  failed;

  /// Precedence, highest first: error → paused → lost → uncertain → No new
  /// match yet → Little sound → Al-Fatiha → Following.
  static DisplayStatus of(ListenState s, DateTime now) {
    final held = s.displayed != null;
    switch (s.phase) {
      case SessionPhase.failed:
        return failed;
      case SessionPhase.paused:
        return paused;
      case SessionPhase.idle:
        return held ? stopped : ready;
      case SessionPhase.connecting:
        return connecting;
      case SessionPhase.reconnecting:
        return reconnecting;
      case SessionPhase.stopping:
        return stopping;
      case SessionPhase.listening:
        break;
    }
    if (!held) return listening;
    switch (s.track.status) {
      case TrackStatus.lost:
        return notMatching;
      case TrackStatus.uncertain:
        return notSure;
      case TrackStatus.tracking:
      case TrackStatus.idle:
        break;
    }
    final since = s.startedAt ?? now;
    final quiet = now.difference(s.lastSoundAt ?? since) >= inferredStateAfter;
    final stale = now.difference(s.confirmedAt ?? since) >= inferredStateAfter;
    if (stale && !quiet) return noNewMatch;
    if (quiet) return littleSound;
    // A position carried over from before this session is held, not
    // confirmed: it waits for the engine like any other.
    if (s.confirmedAt == null || s.track.status != TrackStatus.tracking) return listening;
    if (s.inFatihaExcursion) return fatiha;
    return following;
  }

  /// Filled only when freshly confirmed; hollow whenever a position is
  /// [held] without that; none when there is nothing trustworthy to mark
  /// (or a Notice explains why the session stopped).
  MarkerFill marker({required bool held}) => switch (this) {
        following || fatiha => MarkerFill.filled,
        ready || paused || failed => MarkerFill.none,
        _ => held ? MarkerFill.hollow : MarkerFill.none,
      };

  /// The engine itself is unsure: the numeral and the current ayah dim. An
  /// app-inferred state never dims them: nothing contradicts the position,
  /// there is only no new evidence.
  bool get engineUnsure => this == notSure || this == notMatching;

  /// The listen session is running (the control offers "Stop following").
  bool get active => switch (this) {
        connecting ||
        listening ||
        following ||
        fatiha ||
        noNewMatch ||
        littleSound ||
        notSure ||
        notMatching ||
        reconnecting ||
        stopping =>
          true,
        _ => false,
      };

  /// The status line's words. Empty for [paused] and [failed]: the Notice speaks.
  String label(AppLocalizations l) => switch (this) {
        ready => l.statusReady,
        stopped => l.statusStopped,
        connecting => l.statusConnecting,
        listening => l.statusListening,
        following => l.statusFollowing,
        fatiha => l.statusFatiha,
        noNewMatch => l.statusNoNewMatch,
        littleSound => l.statusLittleSound,
        notSure => l.statusNotSure,
        notMatching => l.statusNotMatching,
        reconnecting => l.statusReconnecting,
        stopping => l.statusStopping,
        paused || failed => '',
      };

  /// The evidence behind the words, if any. [ayah] is the ayah on screen.
  String? caption(AppLocalizations l, int? ayah) => switch (this) {
        ready => l.captionReady,
        stopped => l.captionStopped,
        connecting => l.captionConnecting,
        listening => l.captionListening,
        noNewMatch => ayah == null ? l.captionNoNewMatch : '${l.captionNoNewMatch} ${l.captionStillShowing(ayah)}',
        littleSound =>
          ayah == null ? l.captionLittleSound : '${l.captionLittleSound} ${l.captionStillShowingConfirmed(ayah)}',
        notSure => l.captionNotSure,
        notMatching => l.captionNotMatching,
        reconnecting => l.captionReconnecting,
        following || fatiha || stopping || paused || failed => null,
      };
}
