import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/audio_source.dart';
import '../../core/audio/pcm.dart';
import '../../core/recognition/models.dart';
import '../../core/recognition/recognition_engine.dart';
import '../../l10n/l10n.dart';
import '../../services/screen_awake.dart';
import 'listen_state.dart';
import 'surah_lock.dart';

/// The listening session: microphone -> recognition engine -> [ListenState].
///
/// A state machine over two interfaces (AudioSource, RecognitionEngine), so it
/// is tested with fakes and works unchanged with an on-device engine later.
///
/// Every session gets a generation number. Callbacks from an older session
/// (stopped, paused, failed or restarted) see a stale number and do nothing,
/// which is what keeps late events from resurrecting a finished session.
class ListenController extends Notifier<ListenState> {
  // Platform services are captured once: cleanup runs during disposal, when
  // reading providers is no longer allowed.
  late AudioSource _audioSource;
  late ScreenAwake _screenAwake;
  RecognitionEngine? _engine;
  StreamSubscription<RecognitionEvent>? _events;
  StreamSubscription<Float32List>? _audio;
  Timer? _warningTimer;
  Timer? _wordTimer;
  int _generation = 0;
  DateTime _lastLevel = DateTime.fromMillisecondsSinceEpoch(0);

  static const _maxTranscript = 50;
  static const _levelInterval = Duration(milliseconds: 80);

  @override
  ListenState build() {
    _audioSource = ref.read(audioSourceProvider);
    _screenAwake = ref.read(screenAwakeProvider);
    ref.onDispose(() {
      _generation++;
      unawaited(_teardown());
    });
    return const ListenState();
  }

  // -- commands -----------------------------------------------------------

  Future<void> start() async {
    if (state.isActive) return;
    final generation = ++_generation;
    state = ListenState(
      phase: SessionPhase.connecting,
      hint: state.hint,
      lock: state.lock,
      readerSurah: state.readerSurah,
      browsing: state.browsing,
      // A tie from the last session is not news about this one.
      track: state.track.withoutTie,
      evidenceStatus: state.evidenceStatus,
      anchor: state.anchor,
      lastSure: state.lastSure,
      startedAt: DateTime.now(),
    );

    final audio = _audioSource;
    bool allowed;
    try {
      allowed = await audio.ensurePermission();
    } catch (_) {
      allowed = false;
    }
    if (generation != _generation) return;
    if (!allowed) {
      _fail(generation, ListenError.micPermission, 'Rafiq needs the microphone to hear the imam.');
      return;
    }

    final settings = ref.read(settingsProvider);
    final engine = ref.read(engineFactoryProvider)(settings.serverAddress);
    _engine = engine;
    _events = engine.events.listen((event) => _onEvent(generation, event));
    if (state.lock != null) engine.lock(SurahLock.window(state.lock!));
    unawaited(engine.start(hint: state.hint));

    try {
      final stream = await audio.start();
      if (generation != _generation) {
        await audio.stop();
        return;
      }
      _audio = stream.listen(
        (samples) => _onAudio(generation, samples),
        onError: (Object e) => _fail(generation, ListenError.microphone, 'The microphone stopped working.'),
      );
    } catch (_) {
      _fail(generation, ListenError.microphone, 'Could not start the microphone.');
      return;
    }
    if (settings.keepScreenOn) unawaited(_screenAwake.enable());
  }

  /// Graceful stop: the chunk being recited is still recognised.
  Future<void> stop() async {
    if (!state.isActive || state.phase == SessionPhase.stopping) return;
    final generation = _generation;
    state = state.copyWith(phase: SessionPhase.stopping, level: 0, livePartial: null, liveWord: null);
    await _stopAudio();
    await _engine?.finish();
    if (generation != _generation) return;
    _generation++;
    await _teardown();
    state = state.copyWith(phase: SessionPhase.idle, level: 0, warning: null);
  }

  /// The app went to the background: stop now, keep what is on screen.
  Future<void> pause() async {
    if (!state.isActive) return;
    _generation++;
    await _teardown();
    state = state.copyWith(phase: SessionPhase.paused, level: 0, livePartial: null, liveWord: null);
  }

  /// Set or clear the hint. The server applies hints when a session starts,
  /// so an active session restarts with it (the screen keeps its position).
  Future<void> setHint(Hint? hint) async {
    final wasActive = state.isActive;
    if (wasActive) {
      _generation++;
      await _teardown();
    }
    state = state.copyWith(hint: hint, phase: wasActive ? SessionPhase.idle : null);
    if (wasActive) await start();
  }

  /// "This is the right surah": recognition looks only there and in the surah
  /// after it (al-Fatiha excepted), and follows the imam on ([SurahLock]),
  /// until [unlock]. Returns the lock this one replaced, for Undo.
  Hint? lockTo(Hint scope) {
    final previous = state.lock;
    _engine?.lock(SurahLock.window(scope));
    state = state.copyWith(
      lock: scope,
      readerSurah: scope is SurahHint ? scope.surah : state.readerSurah,
      browsing: false,
      readerOnTie: false,
    );
    return previous;
  }

  void unlock() {
    _engine?.lock(null);
    state = state.copyWith(lock: null);
  }

  /// Undo of [lockTo]: back to [lock] (null: unlocked).
  void restoreLock(Hint? lock) => lock == null ? unlock() : lockTo(lock);

  /// "The imam is here." Shown at once; the server continues from there. A
  /// lock moves to his surah first, so recognition can follow him there.
  void setPosition(Position position) {
    final moved = SurahLock.correct(state.lock, position);
    if (moved != null) _engine?.lock(SurahLock.window(moved));
    _engine?.setPosition(position.verseId);
    // The user's word is committed evidence for where Taraweeh got to.
    _progress(position);
    state = state.copyWith(
      lock: moved ?? state.lock,
      track: TrackState(position: position, status: TrackStatus.tracking, confidence: 1),
      evidenceStatus: TrackStatus.tracking,
      readerSurah: position.surah,
      browsing: false,
      readerOnTie: false,
      // The user said where the imam is, Al-Fatiha included: show exactly that.
      anchor: position.surah == 1 ? null : position,
      lastSure: position,
      confirmedAt: DateTime.now(),
    );
  }

  /// Open a surah by hand (index, next/previous). Following pauses.
  void browse(int surah) => state = state.copyWith(readerSurah: surah, browsing: true, readerOnTie: false);

  /// Back to following the imam.
  void followImam() =>
      state = state.copyWith(browsing: false, readerSurah: state.track.showing?.surah ?? state.readerSurah);

  void dismissError() {
    if (state.phase == SessionPhase.failed) {
      state = state.copyWith(phase: SessionPhase.idle, error: null, errorMessage: null);
    }
  }

  // -- events -------------------------------------------------------------

  void _onAudio(int generation, Float32List samples) {
    if (generation != _generation) return;
    _engine?.addAudio(samples);
    final now = DateTime.now();
    if (now.difference(_lastLevel) >= _levelInterval) {
      _lastLevel = now;
      final level = peakLevel(samples);
      state = state.copyWith(level: level, lastSoundAt: level >= quietLevel ? now : state.lastSoundAt);
    }
  }

  void _onEvent(int generation, RecognitionEvent event) {
    if (generation != _generation) return;
    switch (event) {
      case EngineReady(:final device):
        state = state.copyWith(phase: SessionPhase.listening, device: device, reconnectAttempt: 0);
      case Heard():
        _onHeard(generation, event);
      case EngineWarning(:final message, :final skippedSeconds):
        _warningTimer?.cancel();
        final text = skippedSeconds == null
            ? message
            : lookupAppLocalizations(ref.read(appLocaleProvider)).warningFellBehind(skippedSeconds.toStringAsFixed(1));
        state = state.copyWith(warning: text);
        _warningTimer = Timer(const Duration(seconds: 6), () {
          if (generation == _generation) state = state.copyWith(warning: null);
        });
      case EngineReconnecting(:final attempt):
        if (state.phase != SessionPhase.stopping) {
          state = state.copyWith(phase: SessionPhase.reconnecting, reconnectAttempt: attempt, livePartial: null);
        }
      case EngineFailure(:final message, :final kind):
        final error = switch (kind) {
          FailureKind.unreachable => ListenError.unreachable,
          FailureKind.server => ListenError.server,
          FailureKind.model => ListenError.model,
          FailureKind.missingModel => ListenError.missingModel,
        };
        _fail(generation, error, message);
      case EngineDone():
        break; // stop() completes the shutdown
    }
  }

  void _onHeard(int generation, Heard heard) {
    final line = TranscriptLine(
      text: heard.text,
      start: heard.start,
      end: heard.end,
      asrMs: heard.asrMs,
      shown: heard.state.position,
      isFinal: heard.isFinal,
    );
    var transcript = state.transcript;
    if (heard.isFinal && heard.text.isNotEmpty) {
      transcript = [...transcript, line];
      if (transcript.length > _maxTranscript) transcript = transcript.sublist(transcript.length - _maxTranscript);
    }
    final firstDetection = state.detectedAfter == null && heard.state.position != null && state.startedAt != null;
    // The reader moves to another surah only on a confident result (or the
    // server confirming a user correction): an unsure guess must not yank
    // the text away. Al-Fatiha at each rakʿah does not move it either: the
    // imam's surah stays open. While browsing, the user decides.
    var reader = state.readerSurah;
    final shown = heard.state.showing;
    final confident = heard.state.status == TrackStatus.tracking && shown != null;
    if (!state.browsing && shown != null) {
      final fatihaExcursion = shown.surah == 1 && reader != null && reader != 1;
      // Before the first position, an open surah (a trusted tie opened it)
      // gives way to the first position, as an empty reader does.
      if (reader == null || state.displayed == null || (confident && !fatihaExcursion)) reader = shown.surah;
    }
    // Where Taraweeh got to: committed results only. A preview, a miss, an
    // unsure result or a prediction (`upcoming`) is not evidence of it.
    final committed = heard.state.position;
    if (heard.isFinal && heard.state.evidence && heard.state.status == TrackStatus.tracking && committed != null) {
      _progress(committed);
    }
    // A surah lock moves on with the imam into the next surah.
    final followed = SurahLock.follow(state.lock, heard);
    if (followed != null) _engine?.lock(SurahLock.window(followed));
    final now = DateTime.now();
    final next = state.copyWith(
      lock: followed ?? state.lock,
      anchor: confident && shown.surah != 1 ? shown : state.anchor,
      lastSure: confident ? shown : state.lastSure,
      confirmedAt: confident ? now : state.confirmedAt,
      readerSurah: reader,
      phase: state.phase == SessionPhase.stopping ? null : SessionPhase.listening,
      track: heard.state,
      // A miss keeps the last verdict with evidence (ListenState.trackStatus).
      evidenceStatus: heard.state.evidence ? heard.state.status : state.evidenceStatus,
      transcript: transcript,
      livePartial: heard.isFinal ? null : line,
      detectedAfter: firstDetection ? now.difference(state.startedAt!) : state.detectedAfter,
      liveWord: _liveWord(generation, heard, now),
    );
    // Before any position, a trusted surah opens in the reader, with no ayah
    // marked, so the imam's ayah can be tapped there; another trusted surah
    // replaces it. A surah opened otherwise (a position, the user, a lock)
    // never moves for it, and a weaker result never closes it.
    final place = next.place;
    final onTie = next.displayed == null && !next.browsing && (next.readerSurah == null || state.readerOnTie);
    state = onTie && place is InSurah
        ? next.copyWith(readerSurah: place.surah, readerOnTie: true)
        : next.copyWith(readerOnTie: next.displayed == null && !next.browsing && state.readerOnTie);
  }

  /// Tell the Taraweeh ledger the imam recited [position] (it leaves
  /// Al-Fatiha out itself).
  void _progress(Position position) =>
      ref.read(taraweehLedgerProvider.notifier).observe(position, ref.read(clockProvider)());

  /// Word highlighting (developer setting): the newest result decides. One
  /// without a word means the engine is not sure, and the word goes at once;
  /// a word whose audio is older than the threshold goes on a timer, even if
  /// no result comes again (the imam stopped, the model fell behind).
  LiveWord? _liveWord(int generation, Heard heard, DateTime now) {
    _wordTimer?.cancel();
    final settings = ref.read(settingsProvider);
    final word = heard.word;
    if (!settings.wordHighlight || word == null) return null;
    final live = LiveWord(word, now.subtract(Duration(milliseconds: heard.asrMs)));
    final stale = Duration(milliseconds: (settings.wordStaleSeconds * 1000).round());
    final left = live.heardAt.add(stale).difference(now);
    if (left <= Duration.zero) return null;
    _wordTimer = Timer(left, () {
      if (generation == _generation && identical(state.liveWord, live)) state = state.copyWith(liveWord: null);
    });
    return live;
  }

  void _fail(int generation, ListenError error, String message) {
    if (generation != _generation) return;
    _generation++;
    unawaited(_teardown());
    state = state.copyWith(
      phase: SessionPhase.failed,
      error: error,
      errorMessage: message,
      level: 0,
      livePartial: null,
      liveWord: null,
    );
  }

  // -- cleanup ------------------------------------------------------------

  Future<void> _stopAudio() async {
    final sub = _audio;
    _audio = null;
    await sub?.cancel();
    try {
      await _audioSource.stop();
    } catch (_) {}
  }

  Future<void> _teardown() async {
    _warningTimer?.cancel();
    _wordTimer?.cancel();
    await _stopAudio();
    final engine = _engine, events = _events;
    _engine = null;
    _events = null;
    await events?.cancel();
    if (engine != null) {
      await engine.cancel();
      await engine.dispose();
    }
    await _screenAwake.disable();
  }
}
