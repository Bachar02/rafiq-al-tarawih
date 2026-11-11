import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../../core/recognition/endpoint.dart';

/// Where the on-device speech model's files are, ready for sherpa-onnx.
class ModelPaths {
  const ModelPaths({required this.encoder, required this.decoder, required this.tokens, required this.name});

  final String encoder;
  final String decoder;
  final String tokens;

  /// The model's name, as the bundle's manifest gives it.
  final String name;
}

/// The speech model is not part of this build (a development build made
/// without `tools/whisper_export/install_model.py`).
class ModelMissing implements Exception {
  const ModelMissing();

  @override
  String toString() => 'This build has no speech model.';
}

/// The on-device speech model: bundled with the app (`assets/models/`), and
/// copied on first use to the app's own storage, where sherpa-onnx can open
/// it by path. Nothing is downloaded: Taraweeh mode works offline from the
/// first run.
///
/// Whisper-base fine-tuned on Quran recitation (Tarteel, Apache 2.0), its
/// vocabulary trimmed to the 660 tokens Quran transcripts use
/// (tools/whisper_export/trim_vocab.py): identical output, 55 MB.
class ModelStore {
  ModelStore(this.directory);

  static const encoder = 'encoder.int8.onnx';
  static const decoder = 'decoder.int8.onnx';
  static const tokens = 'tokens.txt';
  static const files = [encoder, decoder, tokens];

  /// The bundle's description of itself (written by install_model.py).
  static const manifestAsset = 'assets/models/manifest.json';

  /// Written last in the installed copy: its presence, equal to the bundled
  /// manifest, is what says the copy is whole and current.
  static const _installed = 'installed.json';

  final Directory directory;

  static Future<Directory> _modelsRoot() async => Directory('${(await getApplicationSupportDirectory()).path}/models');

  String path(String file) => '${directory.path}/$file';

  int get installedBytes => files.fold(0, (sum, f) {
        final file = File(path(f));
        return sum + (file.existsSync() ? file.lengthSync() : 0);
      });

  /// The bundled model, copied to the app's storage if it is not there yet
  /// (the first time, or after an update brought a new model). [onProgress]
  /// gets 0..1 while copying. Throws [ModelMissing] if the build has none,
  /// and a [FileSystemException] if it cannot be copied (storage full).
  static Future<ModelPaths> prepare({void Function(double)? onProgress}) async {
    final String manifestText;
    try {
      manifestText = await rootBundle.loadString(manifestAsset, cache: false);
    } catch (_) {
      throw const ModelMissing();
    }
    final manifest = jsonDecode(manifestText) as Map<String, dynamic>;
    final name = manifest['model'] as String;
    final sizes = {
      for (final e in (manifest['files'] as Map<String, dynamic>).entries)
        e.key: (e.value as Map<String, dynamic>)['bytes'] as int,
    };
    if (!files.every(sizes.containsKey)) throw const ModelMissing();

    final root = await _modelsRoot();
    final store = ModelStore(Directory('${root.path}/$name-v${manifest['version']}'));
    final marker = File(store.path(_installed));
    final whole = marker.existsSync() &&
        marker.readAsStringSync() == manifestText &&
        files.every((f) => File(store.path(f)).existsSync() && File(store.path(f)).lengthSync() == sizes[f]);
    if (!whole) {
      if (marker.existsSync()) marker.deleteSync();
      await store.directory.create(recursive: true);
      final total = sizes.values.fold<int>(0, (a, b) => a + b);
      var done = 0;
      for (final f in files) {
        final target = File(store.path(f));
        if (!(target.existsSync() && target.lengthSync() == sizes[f])) {
          final data = await rootBundle.load('assets/models/$f');
          final part = File('${target.path}.part');
          await part.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
          if (part.lengthSync() != sizes[f]) {
            part.deleteSync();
            throw FileSystemException('the copy of $f is incomplete', part.path);
          }
          part.renameSync(target.path);
        }
        done += sizes[f]!;
        onProgress?.call(done / total);
      }
      await marker.writeAsString(manifestText, flush: true);
      // Older models and development downloads: no longer needed.
      for (final other in root.listSync()) {
        if (other.path != store.directory.path) {
          try {
            other.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    }
    return ModelPaths(
        encoder: store.path(encoder), decoder: store.path(decoder), tokens: store.path(tokens), name: name);
  }
}

/// What the development server offers for the benchmark: test clips.
class DevManifest {
  DevManifest(this.clips);

  factory DevManifest.fromJson(Map<String, dynamic> json) =>
      DevManifest((json['clips'] as List).cast<Map<String, dynamic>>().map(BenchClip.fromJson).toList());

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
      throw StateError('The server has no test clips (run tools/whisper_export/prepare_clips.py on the laptop).');
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
