import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/recognition/endpoint.dart';

/// The on-device speech model files: where they live and how they arrive.
///
/// Dev builds download them from the Rafiq server (`/dev/asr`, see
/// tools/whisper_export). The store builds fetch the same files from a CDN
/// or Play Asset Delivery; only [install]'s source changes.
class ModelStore {
  ModelStore(this.directory);

  static const encoder = 'quran-base-encoder.int8.onnx';
  static const decoder = 'quran-base-decoder.int8.onnx';
  static const tokens = 'quran-base-tokens.txt';
  static const files = [encoder, decoder, tokens];

  final Directory directory;

  static Future<ModelStore> open() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/models/quran-base');
    await dir.create(recursive: true);
    return ModelStore(dir);
  }

  String path(String file) => '${directory.path}/$file';

  bool get isInstalled => files.every((f) => File(path(f)).existsSync() && File(path(f)).lengthSync() > 0);

  int get installedBytes => files.fold(0, (sum, f) {
        final file = File(path(f));
        return sum + (file.existsSync() ? file.lengthSync() : 0);
      });

  /// Download the model from the dev server. [onProgress] gets 0..1.
  /// Each file is written to `.part` and renamed only once complete and the
  /// expected size, so an interrupted download never leaves a broken model.
  Future<DevManifest> install(String serverAddress, {void Function(double)? onProgress}) async {
    final manifest = await fetchManifest(serverAddress);
    final sizes = {for (final f in files) f: manifest.files[f]};
    if (sizes.values.any((s) => s == null)) {
      throw StateError('The server has no exported model (run tools/whisper_export/export_quran_whisper.py).');
    }
    final total = sizes.values.fold<int>(0, (a, b) => a + b!);
    var done = 0;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      for (final f in files) {
        final target = File(path(f));
        if (target.existsSync() && target.lengthSync() == sizes[f]) {
          done += sizes[f]!;
          onProgress?.call(done / total);
          continue;
        }
        final part = File('${target.path}.part');
        final request = await client.getUrl(devFileUri(serverAddress, f));
        final response = await request.close();
        if (response.statusCode != 200) throw HttpException('download of $f failed: HTTP ${response.statusCode}');
        final sink = part.openWrite();
        try {
          await for (final chunk in response) {
            sink.add(chunk);
            done += chunk.length;
            onProgress?.call(done / total);
          }
        } finally {
          await sink.close();
        }
        if (part.lengthSync() != sizes[f]) {
          part.deleteSync();
          throw HttpException('download of $f was incomplete');
        }
        part.renameSync(target.path);
      }
    } finally {
      client.close(force: true);
    }
    return manifest;
  }

  Future<void> uninstall() async {
    for (final f in files) {
      final file = File(path(f));
      if (file.existsSync()) file.deleteSync();
    }
  }
}

/// What the dev server offers: model files and the validation clips.
class DevManifest {
  DevManifest(this.files, this.clips);

  factory DevManifest.fromJson(Map<String, dynamic> json) => DevManifest(
        (json['files'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
        (json['clips'] as List).cast<Map<String, dynamic>>().map(BenchClip.fromJson).toList(),
      );

  final Map<String, int> files;
  final List<BenchClip> clips;
}

/// One validation clip (see tools/whisper_export/prepare_clips.py).
class BenchClip {
  const BenchClip({
    required this.name,
    required this.verseId,
    required this.ref,
    required this.room,
    required this.seconds,
    required this.serverText,
    required this.serverMs,
  });

  factory BenchClip.fromJson(Map<String, dynamic> j) => BenchClip(
        name: j['name'] as String,
        verseId: j['verse_id'] as int,
        ref: j['ref'] as String,
        room: j['room'] as String,
        seconds: (j['seconds'] as num).toDouble(),
        serverText: j['server_text'] as String,
        serverMs: (j['server_ms'] as num).toInt(),
      );

  final String name;
  final int verseId;
  final String ref;
  final String room;
  final double seconds;
  final String serverText;
  final int serverMs;
}

Uri devManifestUri(String address) => healthUri(address).replace(path: '/dev/asr/manifest');

Uri devFileUri(String address, String file) => healthUri(address).replace(path: '/dev/asr/files/$file');

Future<DevManifest> fetchManifest(String serverAddress) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final response = await (await client.getUrl(devManifestUri(serverAddress))).close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 404) {
      throw StateError('The server has no exported model (run tools/whisper_export on the laptop).');
    }
    if (response.statusCode != 200) throw HttpException('manifest: HTTP ${response.statusCode}');
    return DevManifest.fromJson(jsonDecode(body) as Map<String, dynamic>);
  } finally {
    client.close(force: true);
  }
}

/// Download one clip's audio as 16 kHz mono float32 (PCM16 WAV on the server).
Future<List<double>> fetchClip(String serverAddress, String name) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final response = await (await client.getUrl(devFileUri(serverAddress, 'clips/$name.wav'))).close();
    if (response.statusCode != 200) throw HttpException('clip $name: HTTP ${response.statusCode}');
    final bytes = await response.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    return decodeWavPcm16(bytes);
  } finally {
    client.close(force: true);
  }
}

/// PCM16 mono WAV -> samples in [-1, 1]. Finds the `data` chunk (headers vary).
List<double> decodeWavPcm16(List<int> bytes) {
  var offset = 12; // "RIFF" size "WAVE"
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = bytes[offset + 4] | bytes[offset + 5] << 8 | bytes[offset + 6] << 16 | bytes[offset + 7] << 24;
    offset += 8;
    if (id == 'data') {
      final end = (offset + size).clamp(0, bytes.length);
      final out = <double>[];
      for (var i = offset; i + 1 < end; i += 2) {
        var v = bytes[i] | bytes[i + 1] << 8;
        if (v >= 0x8000) v -= 0x10000;
        out.add(v / 32768.0);
      }
      return out;
    }
    offset += size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('no data chunk in WAV');
}
