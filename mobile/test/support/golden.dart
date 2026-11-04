/// Golden screenshot support: the app's real fonts and a comparator that
/// tolerates rasterisation noise but not visible change (test/golden/README.md).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Goldens are rendered and compared on Linux only: the CI runner, or the
/// Docker image used by `tool/goldens.sh`. Other systems rasterise text
/// differently, so their renders would not match.
final String? goldenSkipReason = Platform.isLinux
    ? null
    : 'Golden screenshots are Linux renders; run tool/goldens.sh check (Docker) '
        'instead of comparing on ${Platform.operatingSystem}.';

/// Font families the screens use; loading fails if one is missing from the bundle.
const requiredFontFamilies = {'AmiriQuran', 'Amiri', 'Newsreader', 'IBMPlexSans', 'IBMPlexSansArabic', 'MaterialIcons'};

/// Loads every font in the bundle's FontManifest.json, so text renders in the
/// app's real typefaces instead of the test font (Ahem), and a glyph a font
/// lacks shows up as it would on a phone.
Future<void> loadAppFonts() async {
  final manifest = (jsonDecode(await rootBundle.loadString('FontManifest.json')) as List).cast<Map<String, dynamic>>();
  final families = {for (final entry in manifest) entry['family'] as String};
  final missing = requiredFontFamilies.difference(families);
  if (missing.isNotEmpty) throw StateError('FontManifest.json lacks $missing (pubspec.yaml fonts).');

  for (final entry in manifest) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// A [LocalFileComparator] that accepts faint anti-aliasing differences and
/// rejects anything visible.
///
/// A pixel counts as *visibly* different when any RGBA channel differs by more
/// than [visibleDelta] (out of 255). One such pixel fails the test: a
/// missing-glyph box, an overflow stripe or a 1 px shift all produce many.
/// Fainter differences (rasteriser rounding across CPUs) pass while they
/// touch at most [maxFaintRatio] of the pixels.
class RubricGoldenComparator extends LocalFileComparator {
  RubricGoldenComparator(super.testFile);

  static const visibleDelta = 24;
  static const maxFaintRatio = 0.01;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final goldenBytes = await getGoldenBytes(golden);
    final result = await GoldenFileComparator.compareLists(imageBytes, goldenBytes);
    if (result.passed) {
      result.dispose();
      return true;
    }
    final verdict = await mismatch(imageBytes, goldenBytes);
    if (verdict == null) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError('$verdict\n$error');
  }

  /// Null when two PNGs match within tolerance, else why they do not.
  @visibleForTesting
  static Future<String?> mismatch(List<int> test, List<int> master) async {
    final a = await _decode(test), b = await _decode(master);
    if (a.width != b.width || a.height != b.height) {
      return 'Size changed: ${a.width}×${a.height} vs golden ${b.width}×${b.height}.';
    }
    final pa = a.rgba, pb = b.rgba;
    var visible = 0, faint = 0;
    for (var i = 0; i < pa.length; i += 4) {
      var delta = 0;
      for (var c = 0; c < 4; c++) {
        final d = (pa[i + c] - pb[i + c]).abs();
        if (d > delta) delta = d;
      }
      if (delta > visibleDelta) {
        visible++;
      } else if (delta > 0) {
        faint++;
      }
    }
    final pixels = pa.length ~/ 4;
    if (visible > 0) return '$visible pixel(s) differ visibly (channel delta > $visibleDelta).';
    if (faint > pixels * maxFaintRatio) {
      return '$faint faint pixel differences, over ${(maxFaintRatio * 100).toStringAsFixed(1)}% of the image.';
    }
    return null;
  }

  static Future<({int width, int height, Uint8List rgba})> _decode(List<int> png) async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final decoded = (width: image.width, height: image.height, rgba: data!.buffer.asUint8List());
    image.dispose();
    codec.dispose();
    return decoded;
  }
}
