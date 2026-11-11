/// The live pipeline: audio in, "where is the imam?" out. A port of
/// `engine/src/rafiq/asr/listener.py`, with one addition for phones.
///
///     samples -> Segmenter -> transcribe -> Tracker -> heard events
///
/// * **partial**: while the imam is still reciting, the words so far in the
///   current breath are transcribed and *previewed* by the tracker.
/// * **final**: when he pauses, the whole chunk is transcribed and
///   *committed*. Only finals count as evidence.
///
/// On a phone, each transcription takes a sizeable share of the audio's own
/// length. Partials are therefore made only while the speech model keeps up
/// with plenty to spare ([ListenerConfig.maxPartialLoad]); otherwise the
/// phone transcribes finals only, and stays current instead of falling behind.
library;

import 'dart:typed_data';

import 'segmenter.dart';
import 'tracker.dart';

/// Speech -> text (16 kHz mono float32; empty if nothing was said).
typedef Transcribe = String Function(Float32List audio);

class ListenerConfig {
  const ListenerConfig({
    this.partialEvery = 0.5,
    this.minPartial = 0.6,
    this.maxPartialLoad = 0.5,
    this.partialDuty = 0.5,
    this.loadSmoothing = 0.3,
  });

  /// Seconds of audio between partials (0 disables them).
  final double partialEvery;

  /// Less speech than this is too little to transcribe.
  final double minPartial;

  /// Partials only while transcription costs less than this share of the
  /// audio's length (1.0: as long as the audio itself).
  final double maxPartialLoad;

  /// The most of its time the speech model spends on partials: after one
  /// that took t seconds, the next waits for t / [partialDuty] seconds of new
  /// audio. On the emulator, back-to-back partials kept the model busy 95% of
  /// the time; a phone doing that for a whole Taraweeh runs hot.
  final double partialDuty;

  /// Weight of the newest measurement in the running load.
  final double loadSmoothing;
}

/// One recognised stretch of audio and what the app should now show.
class HeardChunk {
  const HeardChunk({
    required this.text,
    required this.start,
    required this.end,
    required this.asrMs,
    required this.state,
    required this.isFinal,
  });

  final String text;
  final double start;
  final double end;
  final int asrMs;
  final TrackerState state;
  final bool isFinal;
}

class Listener {
  Listener(this.segmenter, this.transcribe, this.tracker,
      {this.config = const ListenerConfig(), int Function()? nowMicros})
      : _now = nowMicros ?? _stopwatch();

  static int Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMicroseconds;
  }

  final Segmenter segmenter;
  final Transcribe transcribe;
  final Tracker tracker;
  final ListenerConfig config;

  /// Microseconds on a monotonic clock (tests pass their own).
  final int Function() _now;
  int _sincePartial = 0; // samples since the last partial or final
  int _partialGap = 0; // samples the next partial waits for (see ListenerConfig.partialDuty)

  /// Transcription time / audio time, smoothed (null until measured).
  double? load;

  bool get partialsOn => config.partialEvery > 0 && (load == null || load! <= config.maxPartialLoad);

  /// Push audio (any length); returns the events it produced. A large block
  /// yields at most one partial, for the latest audio.
  List<HeardChunk> feed(Float32List samples) {
    final out = [for (final seg in segmenter.push(samples)) _recognise(seg, isFinal: true)];
    _sincePartial += samples.length;
    if (out.isNotEmpty) {
      _sincePartial = 0;
    } else if (partialsOn && _sincePartial >= config.partialEvery * engineSampleRate && _sincePartial >= _partialGap) {
      final seg = segmenter.inProgress(config.minPartial);
      if (seg != null) {
        _sincePartial = 0;
        final partial = _recognise(seg, isFinal: false);
        _partialGap = (partial.asrMs / 1000 / config.partialDuty * engineSampleRate).round();
        out.add(partial);
      }
    }
    return out;
  }

  /// Drop pending audio and [samples] not fed (see [Segmenter.skip]).
  void skip(int samples) {
    segmenter.skip(samples);
    _sincePartial = 0;
  }

  /// End of stream.
  List<HeardChunk> flush() => [for (final seg in segmenter.flush()) _recognise(seg, isFinal: true)];

  HeardChunk _recognise(Segment seg, {required bool isFinal}) {
    final t0 = _now();
    final text = transcribe(seg.audio);
    final micros = _now() - t0;
    final seconds = seg.audio.length / engineSampleRate;
    if (seconds > 0) {
      final measured = micros / 1e6 / seconds;
      load = load == null ? measured : load! + config.loadSmoothing * (measured - load!);
    }
    final state = isFinal ? tracker.update(text) : tracker.preview(text);
    return HeardChunk(
      text: text,
      start: seg.start,
      end: seg.end,
      asrMs: micros ~/ 1000,
      state: state,
      isFinal: isFinal,
    );
  }
}
