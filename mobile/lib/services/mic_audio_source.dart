import 'dart:typed_data';

import 'package:record/record.dart';

import '../core/audio/audio_source.dart';
import '../core/audio/pcm.dart';

/// The phone's microphone, as 16 kHz mono float32.
///
/// Asks the OS for 16 kHz PCM16 directly (it resamples natively, which is
/// cheaper and better than doing it in Dart). Voice-call processing is turned
/// off: echo cancellation and noise suppression treat long tajweed vowels as
/// noise and eat them.
class MicAudioSource implements AudioSource {
  MicAudioSource() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: sampleRate,
    numChannels: 1,
    autoGain: true,
    echoCancel: false,
    noiseSuppress: false,
  );

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<Stream<Float32List>> start() async {
    final decoder = Pcm16Decoder();
    final bytes = await _recorder.startStream(_config);
    return bytes.map(decoder.convert);
  }

  @override
  Future<void> stop() async {
    if (await _recorder.isRecording()) await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
