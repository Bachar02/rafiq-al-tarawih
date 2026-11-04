import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// The phone's share sheet. An interface so tests (and screens) never touch
/// the platform plugin directly.
abstract interface class Sharer {
  Future<void> shareText(String text);

  /// Share [png] as an image file named [fileName], with [text] alongside
  /// for apps that take both.
  Future<void> shareImage(Uint8List png, {required String fileName, String? text});
}

class PlatformSharer implements Sharer {
  const PlatformSharer();

  @override
  Future<void> shareText(String text) => SharePlus.instance.share(ShareParams(text: text));

  @override
  Future<void> shareImage(Uint8List png, {required String fileName, String? text}) async {
    // The share sheet needs a file. The cache directory is the OS's to clear.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: text),
    );
  }
}
