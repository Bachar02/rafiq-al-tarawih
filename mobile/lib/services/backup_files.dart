import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Where a backup goes and comes from: a file the user chooses, through the
/// phone's own file picker (tests replace it).
abstract interface class BackupFiles {
  /// Lets the user save [text] as [name] where they choose. False if they
  /// cancelled.
  Future<bool> save(String name, String text);

  /// Lets the user pick a file, and returns its text. Null if they
  /// cancelled.
  Future<String?> open();

  /// Whether [open] is possible on this phone.
  bool get canOpen;
}

/// Android: the system's "Save to" and "Open" screens (the Storage Access
/// Framework, android/.../BackupFiles.kt): Downloads, Drive, a memory card,
/// with no storage permission. Elsewhere: the share sheet to save, no open.
class PlatformBackupFiles implements BackupFiles {
  const PlatformBackupFiles();

  static const _native = MethodChannel('app.rafiq.rafiq/files');

  @override
  bool get canOpen => Platform.isAndroid;

  @override
  Future<bool> save(String name, String text) async {
    if (Platform.isAndroid) return await _native.invokeMethod<bool>('save', {'name': name, 'text': text}) ?? false;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(text, encoding: utf8, flush: true);
    final result = await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/json')]));
    return result.status != ShareResultStatus.dismissed;
  }

  @override
  Future<String?> open() async {
    if (!Platform.isAndroid) throw UnsupportedError('opening a backup');
    return _native.invokeMethod<String>('open');
  }
}
