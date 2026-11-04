// Host-side cost proxy for the R2 spike: build + layout + paint time with the
// real fonts. (The old eager per-surah column it replaced took ~300 ms to lay
// out Al-Baqarah on the same machine: PLAN.md §18.) Debug JIT on a laptop: absolute numbers mean nothing, ratios do. The
// deciding numbers come from integration_test/quran_view_perf_test.dart on a
// phone.
//
//   RAFIQ_PERF=1 flutter test test/perf/quran_view_cost_test.dart
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/theme.dart';
import 'package:rafiq/features/quran_view/quran_view.dart';
import 'package:rafiq/l10n/l10n.dart';

import '../support/fakes.dart';
import '../support/golden.dart';

final _enabled = Platform.environment['RAFIQ_PERF'] == '1';

void main() {
  final quran = loadQuran();
  final names = loadSurahNames();
  int id(int s, int a) => quran.verseId(s, a)!;

  setUpAll(() async {
    if (_enabled) await loadAppFonts();
  });

  Future<Duration> timed(Future<void> Function() f) async {
    final w = Stopwatch()..start();
    await f();
    return w.elapsed;
  }

  String ms(Iterable<Duration> d) {
    final v = d.map((e) => e.inMicroseconds / 1000).toList()..sort();
    final p90 = v[(0.9 * (v.length - 1)).round()];
    return 'median ${v[v.length ~/ 2].toStringAsFixed(1)} ms, p90 ${p90.toStringAsFixed(1)} ms, '
        'worst ${v.last.toStringAsFixed(1)} ms (n=${v.length})';
  }

  Widget app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: child));

  for (final scale in [1.0, 1.6]) {
    testWidgets('cost at text size $scale', (tester) async {
      tester.view.physicalSize = const Size(720, 1600); // A32: 720 × 1600
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      // New: opening at Al-Baqarah.
      final open = <Duration>[];
      for (var i = 0; i < 3; i++) {
        await tester.pumpWidget(app(const SizedBox()));
        open.add(await timed(() async {
          await tester.pumpWidget(app(QuranView(
            quran: quran,
            names: names,
            initialVerse: id(2, 1),
            textScale: scale,
            live: true,
            current: pos(2, 1),
          )));
          await tester.pump();
        }));
      }

      // Scrolling: 60 frames of 40 px (a brisk read) through Al-Baqarah.
      final gesture = await tester.startGesture(tester.getCenter(find.byType(QuranView)));
      final scroll = <Duration>[];
      for (var i = 0; i < 60; i++) {
        await gesture.moveBy(const Offset(0, -40));
        scroll.add(await timed(() => tester.pump(const Duration(milliseconds: 16))));
      }
      await gesture.up();

      // Jumps across the Quran.
      final controller = QuranViewController();
      await tester.pumpWidget(app(QuranView(
        quran: quran,
        names: names,
        initialVerse: 1,
        textScale: scale,
        controller: controller,
      )));
      await tester.pump();
      final jumps = <Duration>[];
      for (final (s, a) in [(2, 255), (114, 1), (18, 1), (3, 1), (36, 1), (2, 1), (67, 1), (9, 1), (55, 1)]) {
        jumps.add(await timed(() async {
          controller.jumpToVerse(id(s, a));
          await tester.pump();
        }));
      }

      // ignore: avoid_print
      print('text size $scale\n'
          '  QuranView open at Al-Baqarah:     ${ms(open)}\n'
          '  QuranView scroll frame:           ${ms(scroll)}\n'
          '  QuranView jump:                   ${ms(jumps)}');
    }, skip: !_enabled);
  }
}
