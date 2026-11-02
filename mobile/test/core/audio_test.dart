import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/core/audio/pcm.dart';
import 'package:rafiq/core/backoff.dart';

Uint8List pcm16(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('Pcm16Decoder', () {
    test('converts to [-1, 1]', () {
      final out = Pcm16Decoder().convert(pcm16([0, 16384, -32768, 32767]));
      expect(out, [0.0, 0.5, -1.0, closeTo(1.0, 1e-4)]);
    });

    test('a sample split across chunks is reassembled', () {
      final bytes = pcm16([1000, -2000, 3000]);
      final decoder = Pcm16Decoder();
      final a = decoder.convert(Uint8List.sublistView(bytes, 0, 3)); // 1.5 samples
      final b = decoder.convert(Uint8List.sublistView(bytes, 3));
      final whole = Pcm16Decoder().convert(bytes);
      expect([...a, ...b], whole);
    });

    test('empty input', () => expect(Pcm16Decoder().convert(Uint8List(0)), isEmpty));
  });

  test('peak level', () {
    expect(peakLevel(Float32List.fromList([0.1, -0.7, 0.3])), closeTo(0.7, 1e-6));
    expect(peakLevel(Float32List(0)), 0);
  });

  group('FrameBatcher', () {
    test('emits frames once enough audio is buffered', () {
      final b = FrameBatcher(frameSamples: 10);
      b.add(Float32List(6));
      expect(b.takeFrame(), isNull);
      b.add(Float32List(6));
      expect(b.takeFrame()!.length, 12);
      expect(b.bufferedSamples, 0);
    });

    test('trimTo keeps the newest audio', () {
      final b = FrameBatcher()
        ..add(Float32List.fromList([1, 2, 3]))
        ..add(Float32List.fromList([4, 5, 6, 7]));
      b.trimTo(5);
      expect(b.takeAll(), [3, 4, 5, 6, 7]);
    });
  });

  test('backoff grows and caps', () {
    expect(backoffDelay(0), Duration.zero);
    expect(backoffDelay(1), const Duration(milliseconds: 500));
    expect(backoffDelay(2), const Duration(seconds: 1));
    expect(backoffDelay(4), const Duration(seconds: 4));
    expect(backoffDelay(9), const Duration(seconds: 8));
    expect(backoffDelay(500), const Duration(seconds: 8));
  });
}
