import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/features/bench/asr_bench_screen.dart';
import 'package:rafiq/services/ondevice/model_store.dart';

List<int> wav(List<int> pcm16, {bool extraChunk = false}) {
  final data = ByteData(pcm16.length * 2);
  for (var i = 0; i < pcm16.length; i++) {
    data.setInt16(i * 2, pcm16[i], Endian.little);
  }
  final body = data.buffer.asUint8List();
  final out = BytesBuilder()
    ..add('RIFF'.codeUnits)
    ..add([0, 0, 0, 0])
    ..add('WAVE'.codeUnits)
    ..add('fmt '.codeUnits)
    ..add([16, 0, 0, 0])
    ..add(List.filled(16, 0));
  if (extraChunk) {
    out
      ..add('LIST'.codeUnits)
      ..add([3, 0, 0, 0])
      ..add([1, 2, 3, 0]); // odd size, padded
  }
  out
    ..add('data'.codeUnits)
    ..add([body.length & 0xff, body.length >> 8 & 0xff, 0, 0])
    ..add(body);
  return out.toBytes();
}

void main() {
  test('WAV decoding finds the data chunk past extra chunks', () {
    expect(decodeWavPcm16(wav([0, 16384, -32768])), [0.0, 0.5, -1.0]);
    expect(decodeWavPcm16(wav([16384], extraChunk: true)), [0.5]);
    expect(() => decodeWavPcm16([82, 73, 70, 70, 0, 0, 0, 0, 87, 65, 86, 69]), throwsFormatException);
  });

  test('word accuracy', () {
    expect(wordAccuracy('والليل إذا سجى', 'والليل إذا سجى'), 1.0);
    expect(wordAccuracy('وَاللَّيْلِ إِذَا سَ', 'والليل إذا سجى'), closeTo(2 / 3, 1e-9));
    expect(wordAccuracy('', 'والليل'), 0.0);
  });

  test('verdict thresholds', () {
    expect(verdict(900), startsWith('GOOD'));
    expect(verdict(2200), startsWith('BORDERLINE'));
    expect(verdict(4000), startsWith('TOO SLOW'));
  });

  test('dev URIs follow the server address', () {
    expect(devManifestUri('192.168.1.14:8765').toString(), 'http://192.168.1.14:8765/dev/asr/manifest');
    expect(devFileUri('192.168.1.14:8765', 'clips/a.wav').toString(),
        'http://192.168.1.14:8765/dev/asr/files/clips/a.wav');
  });
}
