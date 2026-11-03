import 'dart:typed_data';

import 'models.dart';

/// Turns live audio into "where is the imam?" events.
///
/// v1 implementation: `ServerRecognitionEngine` (the laptop server over a
/// WebSocket). Phase 6 adds an on-device engine behind this same interface,
/// so nothing in the UI changes.
///
/// Lifecycle: [start] once, [addAudio] many times, then [finish] (graceful:
/// the last chunk is still recognised) or [cancel] (immediate). Every outcome,
/// including failures and reconnects, arrives on [events].
abstract interface class RecognitionEngine {
  Stream<RecognitionEvent> get events;

  /// Connect and prepare. Completes when the attempt has been made; whether it
  /// worked is reported on [events] (EngineReady or EngineFailure).
  Future<void> start({Hint? hint});

  /// 16 kHz mono float32 samples, any length. Buffered while not connected.
  void addAudio(Float32List samples);

  /// Keep recognition inside this surah/juz (null: search everywhere again).
  /// Remembered for the whole session, including reconnects.
  void lock(Hint? scope);

  /// The user says the imam is at [verseId]; recognition continues from there.
  void setPosition(int verseId);

  /// Stop sending audio, let the engine finish, then close. Emits EngineDone.
  Future<void> finish();

  /// Close immediately.
  Future<void> cancel();

  /// Release everything, including [events]. The engine cannot be reused.
  Future<void> dispose();
}

/// Creates an engine for a server address as the user typed it (overridable in tests).
typedef RecognitionEngineFactory = RecognitionEngine Function(String serverAddress);
