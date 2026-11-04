/// The golden tolerance (test/golden/README.md): rasteriser noise passes,
/// anything visible fails. Pure image arithmetic, so it runs on every OS.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import '../support/golden.dart';

const side = 40; // 1600 pixels: 1% is 16

/// A [side]×[side] mid-grey PNG, with [edit] applied to its RGBA bytes first.
Future<List<int>> png({int width = side, void Function(Uint8List rgba)? edit}) async {
  final rgba = Uint8List(width * side * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    rgba
      ..[i] = 120
      ..[i + 1] = 110
      ..[i + 2] = 100
      ..[i + 3] = 255;
  }
  edit?.call(rgba);
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, width, side, ui.PixelFormat.rgba8888, done.complete);
  final image = await done.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Shift the red channel of the first [count] pixels by [delta].
void Function(Uint8List) shift(int count, int delta) => (rgba) {
      for (var p = 0; p < count; p++) {
        rgba[p * 4] += delta;
      }
    };

void main() {
  Future<String?> compare(Future<List<int>> a, Future<List<int>> b) async =>
      RubricGoldenComparator.mismatch(await a, await b);

  test('identical images match', () async {
    expect(await compare(png(), png()), isNull);
  });

  test('faint noise on up to 1% of pixels passes', () async {
    expect(await compare(png(edit: shift(16, RubricGoldenComparator.visibleDelta)), png()), isNull);
  });

  test('faint noise on more than 1% of pixels fails', () async {
    expect(await compare(png(edit: shift(17, 3)), png()), contains('faint'));
  });

  test('a single visibly different pixel fails', () async {
    expect(await compare(png(edit: shift(1, RubricGoldenComparator.visibleDelta + 1)), png()), contains('visibly'));
  });

  test('a size change fails', () async {
    expect(await compare(png(width: side + 1), png()), contains('Size changed'));
  });
}
