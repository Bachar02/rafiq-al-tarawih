import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/features/listen/listen_controller.dart';
import 'package:rafiq/features/listen/listen_state.dart';

import '../support/fakes.dart';

void main() {
  late Harness h;
  late ProviderContainer container;
  ListenController controller() => container.read(listenControllerProvider.notifier);
  ListenState state() => container.read(listenControllerProvider);

  setUp(() async {
    h = await Harness.create(prefs: {'server_address': '192.168.1.9:8765'});
    container = h.container();
  });
  tearDown(() => container.dispose());

  test('start: connecting, then listening once the engine is ready', () async {
    await controller().start();
    expect(state().phase, SessionPhase.connecting);
    expect(h.addresses, ['192.168.1.9:8765']);
    expect(h.engine.started, isTrue);
    expect(h.audio.capturing, isTrue);
    expect(h.awake.enabled, isTrue);

    h.engine.emit(const EngineReady(device: 'cuda'));
    expect(state().phase, SessionPhase.listening);
    expect(state().device, 'cuda');
  });

  test('audio flows to the engine and drives the level meter', () async {
    await controller().start();
    h.audio.push(Float32List.fromList(List.filled(1600, 0.5)));
    await pumpEventQueue();
    expect(h.engine.samples, 1600);
    expect(state().level, closeTo(0.5, 1e-6));
  });

  test('partials preview, finals commit to the transcript', () async {
    await controller().start();
    h.engine.emit(const EngineReady());
    h.engine.emit(heard(at(93, 2), isFinal: false, text: 'والضحى'));
    expect(state().track.position, pos(93, 2));
    expect(state().livePartial?.text, 'والضحى');
    expect(state().transcript, isEmpty);
    expect(state().detectedAfter, isNotNull);

    h.engine.emit(heard(at(93, 2), text: 'والضحى والليل'));
    expect(state().livePartial, isNull);
    expect(state().transcript.single.text, 'والضحى والليل');
  });

  test('denied microphone: clear error, nothing else started', () async {
    h.audio.permission = false;
    await controller().start();
    expect(state().phase, SessionPhase.failed);
    expect(state().error, ListenError.micPermission);
    expect(h.engines, isEmpty);
    expect(h.awake.enabled, isFalse);
  });

  test('unreachable server: error, mic released, late events ignored', () async {
    await controller().start();
    final engine = h.engine;
    engine.emit(const EngineFailure('Cannot reach', kind: FailureKind.unreachable));
    await pumpEventQueue();
    expect(state().phase, SessionPhase.failed);
    expect(state().error, ListenError.unreachable);
    expect(h.audio.capturing, isFalse);
    expect(engine.cancelled && engine.disposed, isTrue);
    expect(h.awake.enabled, isFalse);
  });

  test('reconnecting keeps the last position; ready resumes', () async {
    await controller().start();
    h.engine.emit(const EngineReady());
    h.engine.emit(heard(at(7, 29)));
    h.engine.emit(const EngineReconnecting(attempt: 2, delay: Duration(seconds: 1)));
    expect(state().phase, SessionPhase.reconnecting);
    expect(state().reconnectAttempt, 2);
    expect(state().track.position, pos(7, 29));
    expect(h.audio.capturing, isTrue); // the mic keeps running

    h.engine.emit(const EngineReady());
    expect(state().phase, SessionPhase.listening);
  });

  test('stop finishes gracefully and keeps the last position on screen', () async {
    await controller().start();
    h.engine.emit(const EngineReady());
    h.engine.emit(heard(at(55, 13)));
    final engine = h.engine;
    await controller().stop();
    expect(engine.finished, isTrue);
    expect(state().phase, SessionPhase.idle);
    expect(state().track.position, pos(55, 13));
    expect(h.audio.capturing, isFalse);
    expect(h.awake.enabled, isFalse);
  });

  test('pause (app backgrounded) cancels at once', () async {
    await controller().start();
    final engine = h.engine;
    await controller().pause();
    expect(state().phase, SessionPhase.paused);
    expect(engine.cancelled, isTrue);
    expect(engine.finished, isFalse);
    expect(engine.disposed, isTrue);
    expect(h.audio.capturing, isFalse);
  });

  test('a hint change restarts the session with the hint', () async {
    await controller().setHint(const JuzHint(30));
    expect(h.engines, isEmpty); // not listening: just remembered
    await controller().start();
    expect(h.engine.startedWith, const JuzHint(30));

    await controller().setHint(const SurahHint(78));
    expect(h.engines, hasLength(2));
    expect(h.engines.first.disposed, isTrue);
    expect(h.engine.startedWith, const SurahHint(78));
    expect(state().phase, SessionPhase.connecting);
  });

  test('a broken microphone mid-session is reported', () async {
    await controller().start();
    h.audio.breakMic();
    await pumpEventQueue();
    expect(state().phase, SessionPhase.failed);
    expect(state().error, ListenError.microphone);
  });

  test('a failed mic start is reported', () async {
    h.audio.failOnStart = true;
    await controller().start();
    expect(state().error, ListenError.microphone);
  });

  test('server warnings are shown', () async {
    await controller().start();
    h.engine.emit(const EngineWarning('fell behind: skipped 2.0 s of audio'));
    expect(state().warning, contains('skipped'));
  });

  test('start twice does not open two sessions', () async {
    await controller().start();
    await controller().start();
    expect(h.engines, hasLength(1));
  });

  test('screen stays dimmable when the user turned keep-awake off', () async {
    h = await Harness.create(prefs: {'keep_screen_on': false});
    container.dispose();
    container = h.container();
    await controller().start();
    expect(h.awake.enabled, isFalse);
  });

  group('user control', () {
    test('a lock is sent with every session and kept across restarts', () async {
      controller().lockTo(const SurahHint(55));
      await controller().start();
      expect(h.engine.locks, [const SurahHint(55)]);
      await controller().stop();
      await controller().start();
      expect(h.engine.locks, [const SurahHint(55)]); // the new engine got it too
      controller().unlock();
      expect(h.engine.locks.last, isNull);
      expect(state().lock, isNull);
    });

    test('"the imam is here" shows at once and reaches the engine', () async {
      await controller().start();
      controller().setPosition(pos(7, 29));
      expect(h.engine.positions, [pos(7, 29).verseId]);
      expect(state().track.position, pos(7, 29));
      expect(state().track.status, TrackStatus.tracking);
      expect(state().readerSurah, 7);
    });

    test('the reader only changes surah on a confident result', () async {
      await controller().start();
      h.engine.emit(const EngineReady());
      h.engine.emit(heard(at(93, 3)));
      expect(state().readerSurah, 93);
      h.engine.emit(heard(at(2, 255, status: TrackStatus.uncertain)));
      expect(state().readerSurah, 93); // unsure: stay
      h.engine.emit(heard(at(2, 255)));
      expect(state().readerSurah, 2); // confident: move
    });

    test('browsing pauses following until the user asks for it', () async {
      await controller().start();
      h.engine.emit(const EngineReady());
      h.engine.emit(heard(at(93, 3)));
      controller().browse(36);
      h.engine.emit(heard(at(93, 4)));
      expect(state().readerSurah, 36);
      expect(state().browsing, isTrue);
      controller().followImam();
      expect(state().readerSurah, 93);
      expect(state().browsing, isFalse);
    });

    test('a position acknowledgement (no text) is not added to the transcript', () async {
      await controller().start();
      h.engine.emit(heard(at(93, 3), text: ''));
      expect(state().transcript, isEmpty);
    });
  });
}
