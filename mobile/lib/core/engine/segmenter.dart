/// Cut a live audio stream into recitation chunks at natural pauses. A port
/// of `engine/src/rafiq/asr/{vad,segmenter}.py` (golden tests).
///
/// Imams breathe and pause between ayahs. Cutting at those pauses keeps words
/// whole, which both the speech model and the matcher want. A reciter who runs
/// on without pausing is cut at the latest short pause, or at
/// [SegmenterConfig.maxChunk] as a last resort, so latency stays bounded.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const engineSampleRate = 16000;

typedef Span = (int, int); // [start, end) in samples

/// Loudness above an adaptive noise floor.
///
/// Tajweed stretches vowels for seconds (madd), and speech-trained models call
/// those sustained tones "not speech", cutting chunks mid-word. Loudness does
/// not care whether the sound is spoken or chanted.
///
/// The floor is learned from the quietest recent frames and remembered across
/// calls; the threshold is also capped at a fraction of the loudest recent
/// level, so listening that starts mid-recitation still hears the imam.
class EnergyVad {
  EnergyVad({
    this.minThreshold = 0.005,
    this.floorRatio = 2.5,
    this.frameMs = 30,
    this.minSilenceMs = 250,
    this.floorDrift = 1.01,
    this.loudFraction = 0.25,
  });

  final double minThreshold;
  final double floorRatio;
  final int frameMs;
  final int minSilenceMs;
  final double floorDrift;
  final double loudFraction;
  double? noiseFloor;
  double? loudLevel;

  double threshold() {
    final floor = noiseFloor, loud = loudLevel;
    if (floor == null || loud == null) return minThreshold;
    return math.max(minThreshold, math.min(floor * floorRatio, loud * loudFraction));
  }

  List<Span> speechSpans(Float32List audio) {
    final frame = engineSampleRate * frameMs ~/ 1000;
    final n = audio.length ~/ frame;
    if (n == 0) return const [];
    final rms = Float64List(n);
    for (var f = 0; f < n; f++) {
      var sum = 0.0;
      for (var i = f * frame; i < (f + 1) * frame; i++) {
        sum += audio[i] * audio[i];
      }
      rms[f] = math.sqrt(sum / frame);
    }
    final sorted = Float64List.fromList(rms)..sort();
    final quiet = _percentile(sorted, 10), loud = _percentile(sorted, 95);
    if (noiseFloor == null || loudLevel == null) {
      noiseFloor = quiet;
      loudLevel = loud;
    } else {
      noiseFloor = math.min(noiseFloor! * floorDrift, quiet);
      loudLevel = math.max(loudLevel! / floorDrift, loud);
    }
    final t = threshold();
    final spans = <Span>[];
    int? start;
    for (var i = 0; i < n; i++) {
      final voiced = rms[i] > t;
      if (voiced && start == null) {
        start = i;
      } else if (!voiced && start != null) {
        spans.add((start * frame, i * frame));
        start = null;
      }
    }
    if (start != null) spans.add((start * frame, n * frame));
    // Merge spans separated by less than the minimum silence.
    final gap = engineSampleRate * minSilenceMs ~/ 1000;
    final merged = <Span>[];
    for (final sp in spans) {
      if (merged.isNotEmpty && sp.$1 - merged.last.$2 < gap) {
        merged[merged.length - 1] = (merged.last.$1, sp.$2);
      } else {
        merged.add(sp);
      }
    }
    return merged;
  }

  /// numpy's default (linear) percentile of an ascending list.
  static double _percentile(Float64List sorted, double q) {
    final pos = q / 100 * (sorted.length - 1);
    final lo = pos.floor(), hi = math.min(lo + 1, sorted.length - 1);
    final t = pos - lo, a = sorted[lo], b = sorted[hi];
    final diff = b - a;
    return t >= 0.5 ? b - diff * (1 - t) : a + diff * t;
  }
}

class SegmenterConfig {
  const SegmenterConfig({
    this.pause = 0.3,
    this.minChunk = 1.0,
    this.lonePause = 1.0,
    this.minSpeech = 0.3,
    this.maxChunk = 6.0,
    this.pad = 0.1,
    this.analyzeEvery = 0.25,
  });

  /// Silence that ends a chunk (seconds).
  final double pause;

  /// Shorter speech waits to be merged with what follows...
  final double minChunk;

  /// ...unless followed by this much silence (a short ayah).
  final double lonePause;

  /// Blips shorter than this are dropped (clicks, coughs).
  final double minSpeech;

  /// Never hold more speech than this.
  final double maxChunk;

  /// Audio kept around each chunk so word edges are not clipped.
  final double pad;
  final double analyzeEvery;
}

class Segment {
  const Segment(this.audio, this.start, this.end);

  final Float32List audio;

  /// Seconds since the stream started.
  final double start;
  final double end;
}

class Segmenter {
  Segmenter(this.vad, [this.config = const SegmenterConfig()]) {
    reset();
  }

  final EnergyVad vad;
  final SegmenterConfig config;

  Float32List _buf = Float32List(0);
  int _offset = 0; // absolute sample index of _buf[0]
  int _unanalyzed = 0;

  void reset() {
    _buf = Float32List(0);
    _offset = 0;
    _unanalyzed = 0;
  }

  static int _s(double seconds) => (seconds * engineSampleRate).toInt();

  /// Add audio; returns any chunks that are now complete.
  List<Segment> push(Float32List samples) {
    final joined = Float32List(_buf.length + samples.length)
      ..setAll(0, _buf)
      ..setAll(_buf.length, samples);
    _buf = joined;
    _unanalyzed += samples.length;
    final out = <Segment>[];
    while (_unanalyzed >= _s(config.analyzeEvery)) {
      _unanalyzed = 0;
      final seg = _tryCut();
      if (seg == null) break;
      out.add(seg);
      _unanalyzed = _buf.length; // re-check the remainder straight away
    }
    return out;
  }

  /// Forget pending audio and jump [samples] ahead, keeping timestamps
  /// continuous (a caller that fell behind drops old audio).
  void skip(int samples) {
    _offset += _buf.length + samples;
    _buf = Float32List(0);
    _unanalyzed = 0;
  }

  /// The speech recited so far that has not ended in a pause yet (what live
  /// partial transcripts are made from).
  Segment? inProgress([double minSpeech = 0.8]) {
    final spans = vad.speechSpans(_buf);
    if (spans.isEmpty || _buf.length - spans.first.$1 < _s(minSpeech)) return null;
    final lo = math.max(0, spans.first.$1 - _s(config.pad));
    return Segment(
      Float32List.fromList(Float32List.sublistView(_buf, lo)),
      (_offset + lo) / engineSampleRate,
      (_offset + _buf.length) / engineSampleRate,
    );
  }

  /// End of stream: whatever speech is left, still split at pauses.
  List<Segment> flush() {
    final out = <Segment>[];
    for (var seg = _tryCut(); seg != null; seg = _tryCut()) {
      out.add(seg);
    }
    final spans = vad.speechSpans(_buf);
    if (spans.isNotEmpty && spans.last.$2 - spans.first.$1 >= _s(config.minSpeech)) {
      out.add(_emit(spans.first.$1, spans.last.$2, _buf.length));
    }
    reset();
    return out;
  }

  Segment? _tryCut() {
    final cfg = config;
    final spans = vad.speechSpans(_buf);
    if (spans.isEmpty) {
      _drop(math.max(0, _buf.length - _s(cfg.pad))); // silence: keep a short tail
      return null;
    }
    // Cut at the FIRST pause that ends a usable chunk.
    final first = spans.first.$1;
    for (var k = 0; k < spans.length; k++) {
      final end = spans[k].$2;
      final nextStart = k + 1 < spans.length ? spans[k + 1].$1 : _buf.length;
      final gap = nextStart - end, speech = end - first;
      if (gap < _s(cfg.pause)) continue;
      if (speech >= _s(cfg.minChunk)) return _emit(first, end, end);
      if (gap >= _s(cfg.lonePause)) {
        if (speech >= _s(cfg.minSpeech)) return _emit(first, end, end);
        _drop(end); // a blip: discard it and look again
        return _tryCut();
      }
      // Short speech then a short pause: it merges with what follows.
    }
    if (_buf.length - first >= _s(cfg.maxChunk)) {
      // Running on: cut at the latest short gap leaving a usable chunk.
      final lo = _s(cfg.minChunk), hi = _s(cfg.maxChunk);
      final inner = [
        for (final sp in spans.sublist(0, spans.length - 1))
          if (lo <= sp.$2 - first && sp.$2 - first <= hi) sp.$2
      ];
      final cut = inner.isNotEmpty ? inner.last : first + hi;
      return _emit(first, cut, cut);
    }
    return null;
  }

  Segment _emit(int start, int end, int cut) {
    final pad = _s(config.pad);
    final lo = math.max(0, start - pad), hi = math.min(_buf.length, end + pad);
    final seg = Segment(
      Float32List.fromList(Float32List.sublistView(_buf, lo, hi)),
      (_offset + lo) / engineSampleRate,
      (_offset + hi) / engineSampleRate,
    );
    _drop(cut);
    return seg;
  }

  void _drop(int n) {
    _buf = Float32List.fromList(Float32List.sublistView(_buf, n));
    _offset += n;
  }
}
