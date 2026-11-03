import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Speech -> text on the phone: the Quran Whisper model via sherpa-onnx.
///
/// Two findings from tools/whisper_export/validate_onnx.py are baked in:
/// * sherpa-onnx's Whisper export drops the fixed 30 s window, so a chunk
///   costs time in proportion to its length (the server pays ~0.4 s always).
/// * Without trailing silence the model drops the last word or two (word
///   accuracy 81% -> 97% with 2 s of silence appended; `tail_paddings` does
///   not help). Every chunk is therefore padded with [silencePad].
class OnDeviceTranscriber {
  OnDeviceTranscriber._(this._recognizer);

  static const silencePad = Duration(seconds: 2);
  static const sampleRate = 16000;

  final sherpa.OfflineRecognizer _recognizer;
  static bool _bindings = false;

  /// Load the model. Slow (hundreds of ms); do it once, off the UI isolate.
  factory OnDeviceTranscriber.load({
    required String encoder,
    required String decoder,
    required String tokens,
    int threads = 2,
  }) {
    if (!_bindings) {
      sherpa.initBindings();
      _bindings = true;
    }
    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: encoder,
          decoder: decoder,
          language: 'ar',
          task: 'transcribe',
        ),
        tokens: tokens,
        numThreads: threads,
        debug: false,
      ),
    );
    return OnDeviceTranscriber._(sherpa.OfflineRecognizer(config));
  }

  /// Transcribe 16 kHz mono float32 audio.
  String transcribe(Float32List audio) {
    final padded = Float32List(audio.length + sampleRate * silencePad.inSeconds)..setAll(0, audio);
    final stream = _recognizer.createStream();
    try {
      stream.acceptWaveform(samples: padded, sampleRate: sampleRate);
      _recognizer.decode(stream);
      return _recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  void dispose() => _recognizer.free();
}

/// One benchmark measurement.
class BenchResult {
  const BenchResult(this.name, this.text, this.ms);
  final String name;
  final String text;
  final int ms;
}

/// Run a benchmark in a background isolate (decoding blocks its thread).
Future<({int loadMs, List<BenchResult> results})> runBenchmark({
  required String encoder,
  required String decoder,
  required String tokens,
  required int threads,
  required List<(String, Float32List)> clips,
}) {
  return Isolate.run(() {
    final load = Stopwatch()..start();
    final asr = OnDeviceTranscriber.load(encoder: encoder, decoder: decoder, tokens: tokens, threads: threads);
    load.stop();
    asr.transcribe(Float32List(sampleRateForWarmup)); // first decode allocates buffers
    final results = <BenchResult>[];
    for (final (name, audio) in clips) {
      final watch = Stopwatch()..start();
      final text = asr.transcribe(audio);
      results.add(BenchResult(name, text, watch.elapsedMilliseconds));
    }
    asr.dispose();
    return (loadMs: load.elapsedMilliseconds, results: results);
  });
}

const sampleRateForWarmup = OnDeviceTranscriber.sampleRate;
