import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/app/components/position_marker.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/features/listen/listen_screen.dart';
import 'package:rafiq/features/listen/widgets/status_line.dart';
import 'package:rafiq/features/settings/settings_screen.dart';
import 'package:rafiq/services/server_health.dart';

import '../support/fakes.dart';

/// Verse ids of the ayahs marked as the imam's current one in the reader.
List<int> currentAyahs(WidgetTester tester) => [
      for (final b in tester.widgetList<AyahBlock>(find.byType(AyahBlock)))
        if (b.tone == AyahTone.current) b.verse.id,
    ];

/// The surah the reader shows.
int readerSurah(WidgetTester tester) => tester.widget<AyahBlock>(find.byType(AyahBlock).first).verse.surah;

/// Tap the given ayah inside the reader (what a real tap on its text does).
Future<void> tapAyah(WidgetTester tester, int surah, int ayah) async {
  final block = find.byWidgetPredicate((w) => w is AyahBlock && w.verse.surah == surah && w.verse.ayah == ayah);
  expect(block, findsOneWidget);
  tester.widget<AyahBlock>(block).onTap!();
}

/// Scroll the settings list until [finder] can be tapped.
Future<void> revealInSettings(WidgetTester tester, Finder finder) => tester.dragUntilVisible(
      finder.hitTestable(),
      find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first,
      const Offset(0, -150),
    );

/// The position marker in the status line.
PositionMarker statusMarker(WidgetTester tester) =>
    tester.widget<PositionMarker>(find.descendant(of: find.byType(StatusLine), matching: find.byType(PositionMarker)));

/// The position header, as screen readers hear it.
Finder header(String label) => find.bySemanticsLabel(label);

void main() {
  late Harness h;

  Future<ProviderContainer> launch(WidgetTester tester, {Size size = const Size(1080, 2340)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await tester.pump();
    // The reader is home; Taraweeh mode is one tap away.
    await tester.tap(find.bySemanticsLabel('Taraweeh: follow the imam'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(ListenScreen)));
  }

  /// Settle animations without waiting on indeterminate spinners forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> startListening(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Start following the imam'));
    await settle(tester);
    h.engine.emit(const EngineReady());
    await settle(tester);
  }

  setUp(() async => h = await Harness.create());

  testWidgets('idle: invites the user to start', (tester) async {
    await launch(tester);
    expect(find.text('Ready to follow'), findsOneWidget);
    expect(find.text('Start following'), findsOneWidget);
    expect(find.bySemanticsLabel('Start following the imam'), findsOneWidget);
    expect(header('No position yet'), findsOneWidget);
    expect(find.byType(PositionMarker), findsNothing); // no position: no marker, no pill
  });

  testWidgets('tap start: connects, then follows the imam with the ayah marked', (tester) async {
    await launch(tester);
    await tester.tap(find.bySemanticsLabel('Start following the imam'));
    await settle(tester);
    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.text('Preparing…'), findsOneWidget);

    h.engine.emit(const EngineReady());
    await settle(tester);
    expect(find.text('Listening for the imam'), findsOneWidget);

    h.engine.emit(heard(at(93, 3)));
    await settle(tester);
    expect(header('Surah Ad-Duha, ayah 3'), findsOneWidget);
    expect(find.text('Ad-Duha · 93 · Juz 30'), findsOneWidget); // curated name, juz from the data
    expect(find.text('الضحى'), findsOneWidget);
    expect(find.text('Following the imam'), findsOneWidget);
    expect(statusMarker(tester).filled, isTrue);
    expect(currentAyahs(tester), [pos(93, 3).verseId]);
    expect(find.bySemanticsLabel('Stop following'), findsOneWidget);
    expect(find.text('Hearing sound'), findsNothing); // the fake mic sends no audio
    expect(find.text('Very little sound'), findsOneWidget);
  });

  testWidgets('ambiguous text shows the alternatives; not sure holds the ayah', (tester) async {
    await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(TrackState(
      position: pos(26, 109),
      status: TrackStatus.uncertain,
      alternatives: [pos(26, 127), pos(26, 145)],
    )));
    await settle(tester);
    expect(find.textContaining('could also be 26:127 · 26:145'), findsOneWidget);
    expect(find.text('Not sure'), findsOneWidget);
    expect(find.text('LAST SURE'), findsOneWidget);
    expect(statusMarker(tester).filled, isFalse);
  });

  testWidgets('an unconfirmed first guess is never shown', (tester) async {
    await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(TrackState(status: TrackStatus.uncertain, pending: pos(7, 29)), isFinal: false));
    await settle(tester);
    expect(find.textContaining('Al-A'), findsNothing);
    expect(find.text('Listening for the imam'), findsOneWidget);
    expect(header('No position yet'), findsOneWidget);
  });

  testWidgets('lost: "Not matching the Quran", the last sure ayah stays', (tester) async {
    await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(at(93, 3)));
    await settle(tester);
    h.engine.emit(heard(at(93, 3, status: TrackStatus.lost)));
    await settle(tester);
    expect(find.text('Not matching the Quran'), findsOneWidget);
    expect(find.textContaining("can't hear"), findsNothing); // no audio-quality claim
    expect(header('Surah Ad-Duha, ayah 3, not sure'), findsOneWidget);
  });

  testWidgets('Al-Fatiha at a new rakʿah: status says so, the imam\'s surah stays', (tester) async {
    await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(at(93, 3)));
    await settle(tester);
    h.engine.emit(heard(at(1, 2)));
    await settle(tester);
    expect(find.text('Al-Fatiha'), findsOneWidget);
    expect(header('Surah Ad-Duha, ayah 3'), findsOneWidget);
    expect(readerSurah(tester), 93);
    expect(statusMarker(tester).filled, isTrue);

    // After al-Fatiha the imam resumes; the header follows again.
    h.engine.emit(heard(at(93, 4)));
    await settle(tester);
    expect(find.text('Following the imam'), findsOneWidget);
    expect(header('Surah Ad-Duha, ayah 4'), findsOneWidget);
  });

  testWidgets('unreachable server: explains and links to settings', (tester) async {
    await launch(tester);
    await tester.tap(find.bySemanticsLabel('Start following the imam'));
    await settle(tester);
    h.engine.emit(
        const EngineFailure('Cannot reach the recognition server at 10.0.2.2:8765', kind: FailureKind.unreachable));
    await settle(tester);
    expect(find.text("Can't reach the recognition server"), findsOneWidget);
    expect(find.text('Start following'), findsOneWidget); // the control returns to Ready
    await tester.ensureVisible(find.text('Test connection'));
    await tester.tap(find.text('Test connection'));
    await settle(tester);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('denied microphone: explains how to allow it', (tester) async {
    h.audio.permission = false;
    await launch(tester);
    await tester.tap(find.bySemanticsLabel('Start following the imam'));
    await settle(tester);
    expect(find.text('Rafiq needs the microphone'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await settle(tester);
    expect(find.text('Rafiq needs the microphone'), findsNothing);
  });

  testWidgets('backgrounded: following paused, resume restarts', (tester) async {
    final container = await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(at(93, 3)));
    await settle(tester);
    // The test binding starts with no lifecycle state (no transitions from
    // it), and a paused binding draws no frames: resumed → paused → resumed.
    // Real async: the controller's teardown awaits a stream cancel, whose
    // root-zone future the fake test clock never completes.
    await tester.runAsync(() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
    expect(find.text('Following paused'), findsOneWidget);
    expect(header('Surah Ad-Duha, ayah 3'), findsOneWidget); // the last position stays
    await tester.ensureVisible(find.text('Resume'));
    await tester.tap(find.text('Resume'));
    await settle(tester);
    expect(container.read(listenControllerProvider).isActive, isTrue);
  });

  testWidgets('hint sheet: pick a juz, see the chip, clear it', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip("Tonight's starting point"));
    await settle(tester);
    expect(find.textContaining('Optional. Rafiq finds the imam without it'), findsOneWidget);
    await tester.tap(find.text('Juz'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Juz 30'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Juz 30'));
    await settle(tester);
    expect(find.text('Tonight: Juz 30'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove hint'));
    await settle(tester);
    expect(find.text('Tonight: Juz 30'), findsNothing);
  });

  testWidgets('settings: test connection reports the server and model', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    expect(find.text('Ḥafṣ ʿan ʿĀṣim'), findsOneWidget); // the riwāya statement
    await revealInSettings(tester, find.text('Test connection'));
    await tester.tap(find.text('Test connection'));
    await settle(tester);
    expect(find.textContaining('Connected · 12 ms · speech model cuda'), findsOneWidget);

    h.health = const ServerHealth.failed('Cannot reach the server. Is it running, and on the same Wi-Fi?');
    await tester.tap(find.text('Test connection'));
    await settle(tester);
    expect(find.textContaining('Is it running, and on the same Wi-Fi'), findsOneWidget);
  });

  testWidgets('settings: an invalid address is rejected and not saved', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await revealInSettings(tester, find.text('Test connection'));
    await tester.enterText(find.byType(TextField), '');
    await settle(tester); // the field scrolls itself into view first
    await revealInSettings(tester, find.text('Test connection'));
    await tester.tap(find.text('Test connection'));
    await settle(tester);
    expect(find.textContaining('Enter the address'), findsOneWidget);
    expect(h.prefs.getString('server_address'), isNull);
  });

  testWidgets('settings: text size previews 93:3 and is saved', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await tester.tap(find.text('Quran text size'));
    await settle(tester);
    final preview = tester.widget<AyahBlock>(find.byType(AyahBlock)).verse;
    expect((preview.surah, preview.ayah), (93, 3));
    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await settle(tester);
    expect(h.prefs.getDouble('text_scale'), greaterThan(1.0));
  });

  testWidgets('settings: appearance switches the theme', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await tester.tap(find.text('Appearance'));
    await settle(tester);
    await tester.tap(find.text('Light'));
    await settle(tester);
    expect(h.prefs.getString('theme_mode'), 'light');
  });

  testWidgets('tap an ayah: "the imam is here" jumps there and tells the server', (tester) async {
    await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(at(93, 2)));
    await settle(tester);

    await tapAyah(tester, 93, 6);
    await settle(tester);
    await tester.tap(find.text('The imam is here'));
    await settle(tester);
    expect(h.engine.positions, [pos(93, 6).verseId]);
    expect(currentAyahs(tester), [pos(93, 6).verseId]);
    expect(header('Surah Ad-Duha, ayah 6'), findsOneWidget);
  });

  testWidgets('lock the surah from the header, then unlock', (tester) async {
    await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(at(55, 13)));
    await settle(tester);

    await tester.tap(find.byTooltip('Stay on this surah'));
    await settle(tester);
    expect(find.textContaining('Al-Fatiha is still recognised'), findsOneWidget);
    await tester.tap(find.text('Stay on this surah'));
    await settle(tester);
    expect(h.engine.locks, [const SurahHint(55)]);

    await tester.tap(find.byTooltip('Locked to Ar-Rahman. Tap to unlock.'));
    await settle(tester);
    expect(h.engine.locks.last, isNull);
  });

  testWidgets('an unsure far guess does not yank the reader or the number', (tester) async {
    await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(at(93, 3)));
    await settle(tester);
    h.engine.emit(heard(at(2, 255, status: TrackStatus.uncertain)));
    await settle(tester);
    expect(readerSurah(tester), 93);
    expect(header('Surah Ad-Duha, ayah 3, not sure'), findsOneWidget);
  });

  testWidgets('browse any surah from the index, then go back to the imam', (tester) async {
    await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(at(93, 3)));
    await settle(tester);

    await tester.tap(find.byTooltip('Surahs'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Yaseen'); // the data's own transliteration still matches
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Ya-Sin'));
    await settle(tester);
    expect(readerSurah(tester), 36);
    expect(find.text('يس'), findsOneWidget); // the column names the surah it shows
    expect(find.text('Back to the imam · 93:3').hitTestable(), findsOneWidget);

    await tester.tap(find.text('Back to the imam · 93:3'));
    await settle(tester);
    expect(find.textContaining('Back to the imam').hitTestable(), findsNothing); // faded out
    expect(currentAyahs(tester), [pos(93, 3).verseId]);
  });

  testWidgets('small phone, largest text: no overflow', (tester) async {
    await launch(tester, size: const Size(960, 1704)); // 320 × 568 logical
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await startListening(tester);
    h.engine.emit(heard(at(2, 282)));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(header('Surah Al-Baqarah, ayah 282'), findsOneWidget);
  });

  testWidgets('scrolling the current ayah away offers the way back', (tester) async {
    await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(at(2, 255)));
    await settle(tester);
    final pill = find.textContaining('Back to the imam').hitTestable();
    expect(pill, findsNothing);

    await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -3000));
    await settle(tester);
    expect(pill, findsOneWidget);
    h.engine.emit(heard(at(2, 256))); // following continues underneath, no auto-scroll back
    await settle(tester);
    expect(pill, findsOneWidget);
    expect(find.text('Back to the imam · 2:256'), findsOneWidget);

    await tester.tap(pill);
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(pill, findsNothing);
    expect(currentAyahs(tester), [pos(2, 256).verseId]);
  });

  testWidgets('Taraweeh mode is dark over a light reader, unless turned off', (tester) async {
    h = await Harness.create(prefs: {'theme_mode': 'light'});
    await launch(tester);
    expect(Theme.of(tester.element(find.byType(ListenScreen))).brightness, Brightness.dark);
    // Settings opened from Taraweeh mode keep its theme.
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness, Brightness.dark);
  });

  testWidgets('light theme renders the same screen', (tester) async {
    h = await Harness.create(prefs: {'theme_mode': 'light', 'dark_during_taraweeh': false});
    await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(at(93, 3)));
    await settle(tester);
    expect(Theme.of(tester.element(find.byType(ListenScreen))).brightness, Brightness.light);
    expect(currentAyahs(tester), [pos(93, 3).verseId]);
  });
}
