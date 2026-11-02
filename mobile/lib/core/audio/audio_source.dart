import 'dart:typed_data';

/// A live source of 16 kHz mono float32 audio (see `pcm.dart`).
///
/// The microphone in v1; a file player for demos or tests later. The listen
/// feature only ever sees this interface.
abstract interface class AudioSource {
  /// Ask for (or check) permission to record. False if the user refused.
  Future<bool> ensurePermission();

  /// Start capturing. The stream ends when [stop] is called.
  Future<Stream<Float32List>> start();

  Future<void> stop();

  Future<void> dispose();
}
