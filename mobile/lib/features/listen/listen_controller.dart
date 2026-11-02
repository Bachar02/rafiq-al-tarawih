import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/audio/pcm.dart';
import '../../core/recognition/models.dart';
import '../../core/recognition/recognition_engine.dart';
import 'listen_state.dart';

/// The listening session: microphone -> recognition engine -> [ListenState].
///
/// A state machine over two interfaces (AudioSource, RecognitionEngine), so it
/// is tested with fakes and works unchanged with an on-device engine later.
///
/// Every session gets a generation number. Callbacks from an older session
/// (stopped, paused, failed or restarted) see a stale number and do nothing,
/// which is what keeps late events from resurrecting a finished session.
class ListenController extends Notifier<ListenState> {
  RecognitionEngine? _engine;
  StreamSubscription<RecognitionEvent>? _events;
  StreamSubscription<Float32List>? _audio;
  Timer? _warningTimer;
  int _generation = 0;
  DateTime _lastLevel = DateTime.fromMillisecondsSinceEpoch(0);

  static const _maxTranscript = 50;
  static const _levelInterval = Duration(milliseconds: 80);

  @override
  ListenState build() {
    ref.onDispose(_teardown);
    return const ListenState();
  }

  // -- commands -----------------------------------------------------------

  Future<void> start() async {
    if (state.isActive) return;
    final generation = ++_generation;
    state = ListenState(
      phase: SessionPhase.connecting,
      hint: state.hint,
      startedAt: DateTime.now(),
    );

    final audio = ref.read(audioSourceProvider);
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
    if (settings.keepScreenOn) unawaited(ref.read(screenAwakeProvider).enable());
  }

  /// Graceful stop: the chunk being recited is still recognised.
  Future<void> stop() async {
    if (!state.isActive || state.phase == SessionPhase.stopping) return;
    final generation = _generation;
    state = state.copyWith(phase: SessionPhase.stopping, level: 0, livePartial: null);
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
    state = state.copyWith(phase: SessionPhase.paused, level: 0, livePartial: null);
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
      state = state.copyWith(level: peakLevel(samples));
    }
  }

  void _onEvent(int generation, RecognitionEvent event) {
    if (generation != _generation) return;
    switch (event) {
      case EngineReady(:final device):
        state = state.copyWith(phase: SessionPhase.listening, device: device, reconnectAttempt: 0);
      case Heard():
        _onHeard(event);
      case EngineWarning(:final message):
        _warningTimer?.cancel();
        state = state.copyWith(warning: message);
        _warningTimer = Timer(const Duration(seconds: 6), () {
          if (generation == _generation) state = state.copyWith(warning: null);
        });
      case EngineReconnecting(:final attempt):
        if (state.phase != SessionPhase.stopping) {
          state = state.copyWith(phase: SessionPhase.reconnecting, reconnectAttempt: attempt, livePartial: null);
        }
      case EngineFailure(:final message, :final kind):
        _fail(generation, kind == FailureKind.unreachable ? ListenError.unreachable : ListenError.server, message);
      case EngineDone():
        break; // stop() completes the shutdown
    }
  }

  void _onHeard(Heard heard) {
    final line = TranscriptLine(
      text: heard.text,
      start: heard.start,
      end: heard.end,
      asrMs: heard.asrMs,
      shown: heard.state.position,
      isFinal: heard.isFinal,
    );
    var transcript = state.transcript;
    if (heard.isFinal) {
      transcript = [...transcript, line];
      if (transcript.length > _maxTranscript) transcript = transcript.sublist(transcript.length - _maxTranscript);
    }
    final firstDetection = state.detectedAfter == null && heard.state.position != null && state.startedAt != null;
    state = state.copyWith(
      phase: state.phase == SessionPhase.stopping ? null : SessionPhase.listening,
      track: heard.state,
      transcript: transcript,
      livePartial: heard.isFinal ? null : line,
      detectedAfter: firstDetection ? DateTime.now().difference(state.startedAt!) : state.detectedAfter,
    );
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
    );
  }

  // -- cleanup ------------------------------------------------------------

  Future<void> _stopAudio() async {
    final sub = _audio;
    _audio = null;
    await sub?.cancel();
    try {
      await ref.read(audioSourceProvider).stop();
    } catch (_) {}
  }

  Future<void> _teardown() async {
    _warningTimer?.cancel();
    await _stopAudio();
    final engine = _engine, events = _events;
    _engine = null;
    _events = null;
    await events?.cancel();
    if (engine != null) {
      await engine.cancel();
      await engine.dispose();
    }
    await ref.read(screenAwakeProvider).disable();
  }
}
