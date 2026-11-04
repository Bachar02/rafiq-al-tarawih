// R2 spike: QuranView scroll and jump performance, on a real phone.
//
//   flutter drive --profile -d <device> \
//     --driver=test_driver/perf_driver.dart \
//     --target=integration_test/quran_view_perf_test.dart
//   python tool/perf_report.py            # table + pass/fail against the budgets
//
// Profile mode only: debug builds are many times slower and say nothing.
// The scenarios are deterministic (fixed verses, fixed fling velocities), so
// runs on different phones and builds are comparable.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rafiq/app/theme.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/data/quran.dart';
import 'package:rafiq/data/surah_names.dart';
import 'package:rafiq/features/quran_view/quran_view.dart';
import 'package:rafiq/l10n/l10n.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real frames at the display's pace, as a user would get them.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late Quran quran;
  late SurahNames names;

  setUpAll(() async {
    quran = await compute(Quran.fromJson, await rootBundle.loadString('assets/quran/quran.json'));
    names = SurahNames.fromJson(await rootBundle.loadString('assets/data/surah-names.json'), quran);
  });

  int id(int s, int a) => quran.verseId(s, a)!;

  Future<QuranViewController> show(
    WidgetTester tester, {
    required int verse,
    required double scale,
    Position? current,
  }) async {
    final controller = QuranViewController();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: QuranView(
            quran: quran,
            names: names,
            initialVerse: verse,
            controller: controller,
            textScale: scale,
            live: current != null,
            current: current,
            followVerse: current?.verseId,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> flings(WidgetTester tester, int count, {double velocity = 2500}) async {
    for (var i = 0; i < count; i++) {
      await tester.fling(find.byType(QuranView), const Offset(0, -500), velocity);
      await tester.pumpAndSettle();
    }
  }

  // Far apart, so every one is a re-anchor (nothing built in between).
  final jumpTargets = [
    (2, 255), (114, 1), (18, 1), (3, 1), (36, 1), (2, 1), (67, 1), (9, 1), (55, 1), (4, 100), //
    (26, 100), (78, 1), (12, 50), (2, 286), (24, 35), (1, 1), (7, 200), (56, 1), (20, 1), (110, 1),
  ];

  for (final scale in [1.0, 1.6]) {
    final tag = 'x${scale.toStringAsFixed(1)}';

    testWidgets('long surah: Al-Baqarah flings, $tag', (tester) async {
      await show(tester, verse: id(2, 1), scale: scale);
      await binding.traceAction(() => flings(tester, 14), reportKey: 'baqarah_$tag');
    });

    testWidgets('cross-surah: the short surahs of juz 30, $tag', (tester) async {
      await show(tester, verse: id(77, 40), scale: scale);
      await binding.traceAction(() => flings(tester, 14), reportKey: 'juz30_$tag');
    });

    testWidgets('navigation jumps, $tag', (tester) async {
      final controller = await show(tester, verse: 1, scale: scale);
      final wall = <int>[];
      await binding.traceAction(() async {
        for (final (s, a) in jumpTargets) {
          final watch = Stopwatch()..start();
          controller.jumpToVerse(id(s, a));
          await tester.pump();
          await tester.pump(); // the post-frame settle of an aligned jump, if any
          wall.add(watch.elapsedMilliseconds);
          await tester.pump(const Duration(milliseconds: 200));
        }
      }, reportKey: 'jumps_$tag');
      binding.reportData!['jump_wall_ms_$tag'] = wall;
    });

    testWidgets('Taraweeh follow: the imam moves ayah by ayah, $tag', (tester) async {
      Position at(int ayah) => Position(verseId: id(2, ayah), surah: 2, ayah: ayah);
      await show(tester, verse: id(2, 1), scale: scale, current: at(1));
      await binding.traceAction(() async {
        for (var ayah = 2; ayah <= 30; ayah++) {
          await tester.pumpWidget(MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.dark(),
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: SafeArea(
                child: QuranView(
                  quran: quran,
                  names: names,
                  initialVerse: id(2, 1),
                  textScale: scale,
                  live: true,
                  current: at(ayah),
                  followVerse: at(ayah).verseId,
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();
        }
      }, reportKey: 'follow_$tag');
    });
  }
}
