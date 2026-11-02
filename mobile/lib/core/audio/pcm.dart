/// Audio plumbing between the microphone and the recognition engine.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// The engine's audio format: 16 kHz mono float32 in [-1, 1].
const sampleRate = 16000;

/// Decodes a stream of little-endian PCM16 byte chunks into float32 samples.
///
/// Platform audio APIs deliver arbitrary byte counts, so a chunk can end in
/// the middle of a 2-byte sample; the odd byte is carried over to the next.
class Pcm16Decoder {
  int? _carry;

  Float32List convert(Uint8List bytes) {
    var offset = 0;
    final total = bytes.length + (_carry == null ? 0 : 1);
    final out = Float32List(total ~/ 2);
    var i = 0;
    if (_carry != null && bytes.isNotEmpty) {
      out[i++] = _sample(_carry!, bytes[0]);
      offset = 1;
      _carry = null;
    }
    for (; offset + 1 < bytes.length; offset += 2) {
      out[i++] = _sample(bytes[offset], bytes[offset + 1]);
    }
    if (offset < bytes.length) _carry = bytes[offset];
    return i == out.length ? out : Float32List.sublistView(out, 0, i);
  }

  static double _sample(int lo, int hi) {
    var v = lo | (hi << 8);
    if (v >= 0x8000) v -= 0x10000;
    return v / 32768.0;
  }
}

/// Peak absolute amplitude, 0..1 (for the input level meter).
double peakLevel(Float32List samples) {
  var peak = 0.0;
  for (final s in samples) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  return math.min(peak, 1.0);
}

/// Collects samples into frames of at least [frameSamples] (~250 ms).
///
/// Sending tiny frames wastes bandwidth and server work; huge ones add
/// latency. While the connection is down, [trimTo] keeps only the newest
/// audio: the app follows the imam *now*.
class FrameBatcher {
  FrameBatcher({this.frameSamples = 4000});

  final int frameSamples;
  final List<Float32List> _blocks = [];
  int _length = 0;

  int get bufferedSamples => _length;

  void add(Float32List samples) {
    if (samples.isEmpty) return;
    _blocks.add(samples);
    _length += samples.length;
  }

  /// A full frame if enough audio is buffered, else null.
  Float32List? takeFrame() => _length >= frameSamples ? takeAll() : null;

  /// Everything buffered, as one frame (possibly empty).
  Float32List takeAll() {
    final out = Float32List(_length);
    var offset = 0;
    for (final b in _blocks) {
      out.setAll(offset, b);
      offset += b.length;
    }
    _blocks.clear();
    _length = 0;
    return out;
  }

  /// Drop the oldest audio until at most [maxSamples] remain.
  void trimTo(int maxSamples) {
    while (_length > maxSamples && _blocks.isNotEmpty) {
      final excess = _length - maxSamples;
      final first = _blocks.first;
      if (first.length <= excess) {
        _blocks.removeAt(0);
        _length -= first.length;
      } else {
        _blocks[0] = Float32List.sublistView(first, excess);
        _length -= excess;
      }
    }
  }
}
