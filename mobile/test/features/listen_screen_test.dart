import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/app/components/position_marker.dart';
import 'package:rafiq/app/components/quran_text.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/listen/listen_screen.dart';
import 'package:rafiq/features/quran_view/quran_view.dart';
import 'package:rafiq/features/reader/reader_screen.dart';
import 'package:rafiq/features/listen/widgets/status_line.dart';
import 'package:rafiq/features/settings/settings_screen.dart';
import 'package:rafiq/services/server_health.dart';

import '../support/fakes.dart';
import '../support/app_nav.dart';

/// Verse ids of the ayahs marked as the imam's current one in the reader.
List<int> currentAyahs(WidgetTester tester) => [
      for (final b in tester.widgetList<AyahBlock>(find.byType(AyahBlock)))
        if (b.tone == AyahTone.current) b.verse.id,
    ];

/// The surah the reader shows: the ayah nearest the middle of the text.
int readerSurah(WidgetTester tester) {
  final middle = tester.getRect(find.byType(QuranView)).center.dy;
  final blocks = find.descendant(of: find.byType(QuranView), matching: find.byType(AyahBlock)).evaluate();
  final nearest = blocks.reduce((a, b) {
    double d(Element e) {
      final box = e.renderObject! as RenderBox;
      return (box.localToGlobal(box.size.center(Offset.zero)).dy - middle).abs();
    }

    return d(a) <= d(b) ? a : b;
  });
  return (nearest.widget as AyahBlock).verse.surah;
}

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

  /// Settle animations without waiting on indeterminate spinners forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> launch(WidgetTester tester, {Size size = const Size(1080, 2340)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await tester.pump();
    // The reader is home; Taraweeh mode is one tap away and starts following.
    await tester.tap(taraweehButton);
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(ListenScreen)));
  }

  /// Tap [finder], then let what it starts finish. Session teardown (stop,
  /// a new hint, leaving the mode) awaits stream cancels on real futures,
  /// which the fake test clock alone never completes: alternate real time
  /// and frames until the chain is done.
  Future<void> tapAndFinish(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);
  }

  /// Entering the mode started a session: the engine becomes ready.
  Future<void> startListening(WidgetTester tester) async {
    h.engine.emit(const EngineReady());
    await settle(tester);
  }

  /// The introduction has been seen: entering starts following at once.
  const introSeen = {'taraweeh_intro_seen': true};

  setUp(() async => h = await Harness.create(prefs: introSeen));

  testWidgets('stopped before any position: ready to follow again', (tester) async {
    await launch(tester);
    await startListening(tester);
    await tapAndFinish(tester, find.bySemanticsLabel('Stop following'));
    expect(find.text('Ready to follow'), findsOneWidget);
    expect(find.text('Start following'), findsOneWidget);
    expect(find.bySemanticsLabel('Start following the imam'), findsOneWidget);
    expect(header('No position yet'), findsOneWidget);
    expect(find.byType(PositionMarker), findsNothing); // no position: no marker, no pill
  });

  testWidgets('one tap from the reader: connects, then follows the imam with the ayah marked', (tester) async {
    await launch(tester);
    expect(find.text('Getting ready…'), findsOneWidget);
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

  testWidgets('the speech model cannot start: says so, and offers to try again', (tester) async {
    await launch(tester);
    h.engine.emit(const EngineFailure('Failed to load model: out of memory', kind: FailureKind.model));
    await settle(tester);
    expect(find.text('The speech model could not start'), findsOneWidget);
    expect(find.textContaining('Close other apps and try again'), findsOneWidget);
    expect(find.textContaining('out of memory'), findsNothing, reason: "the engine's words are for developers");
    await tester.ensureVisible(find.text('Try again'));
    await tapAndFinish(tester, find.text('Try again'));
    expect(h.engines, hasLength(2), reason: 'a new session');
  });

  testWidgets('a build without the speech model: says so, and where the alternative is', (tester) async {
    await launch(tester);
    h.engine.emit(const EngineFailure('This build has no speech model.', kind: FailureKind.missingModel));
    await settle(tester);
    expect(find.text('This build has no speech model'), findsOneWidget);
    expect(find.textContaining('Settings → Developer'), findsOneWidget);
  });

  testWidgets('the phone fell behind: a short notice, in the interface language', (tester) async {
    await launch(tester);
    await startListening(tester);
    h.engine.emit(const EngineWarning.fellBehind(3.24));
    await settle(tester);
    expect(find.text('The phone fell behind and skipped 3.2 s to catch up with the imam.'), findsOneWidget);
  });

  testWidgets('settings: the server is a developer option, off by default', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    expect(find.text('Test connection'), findsNothing, reason: 'recognition is on the phone');
    await revealInSettings(tester, find.text('Recognise on a computer'));
    await tester.tap(find.text('Recognise on a computer'));
    await settle(tester);
    expect(h.prefs.getBool('recognition_server'), isTrue);
    await revealInSettings(tester, find.text('Test connection'));
    expect(find.text('Test connection'), findsOneWidget);
  });

  testWidgets('denied microphone: explains how to allow it', (tester) async {
    h.audio.permission = false;
    await launch(tester);
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
    // it), and a paused binding draws no frames. The states follow Android's
    // order (AppLifecycleListener asserts it): resumed → inactive → hidden →
    // paused, and back.
    // Real async: the controller's teardown awaits a stream cancel, whose
    // root-zone future the fake test clock never completes.
    await tester.runAsync(() async {
      for (final state in [
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
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
    await tapAndFinish(tester, find.text('Juz 30'));
    expect(find.text('Tonight: Juz 30'), findsOneWidget); // shown while the imam is not found yet
    expect(h.engine.startedWith, const JuzHint(30)); // the session restarted with it

    await tapAndFinish(tester, find.byTooltip('Remove hint'));
    expect(find.text('Tonight: Juz 30'), findsNothing);
  });

  testWidgets('settings: test connection reports the server and model', (tester) async {
    h = await Harness.create(prefs: {...introSeen, 'recognition_server': true});
    await launch(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await revealInSettings(tester, find.text('Ḥafṣ ʿan ʿĀṣim'));
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
    h = await Harness.create(prefs: {...introSeen, 'recognition_server': true});
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

    await tapAyah(tester, 93, 4);
    await settle(tester);
    await tester.tap(find.text('The imam is here'));
    await settle(tester);
    expect(h.engine.positions, [pos(93, 4).verseId]);
    expect(currentAyahs(tester), [pos(93, 4).verseId]);
    expect(header('Surah Ad-Duha, ayah 4'), findsOneWidget);
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
    expect(h.engine.locks, [const SurahRange(55, 56)]);
    expect(find.text('Staying on Ar-Rahman, then the next surah'), findsOneWidget);

    // Undo: back to no lock.
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(h.engine.locks.last, isNull);
    expect(find.byTooltip('Stay on this surah'), findsOneWidget);

    // Lock again, then unlock from the header.
    await tester.tap(find.byTooltip('Stay on this surah'));
    await settle(tester);
    await tester.tap(find.text('Stay on this surah'));
    await settle(tester);
    expect(h.engine.locks.last, const SurahRange(55, 56));
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

    await tester.drag(find.byType(QuranView), const Offset(0, -3000));
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
    h = await Harness.create(prefs: {...introSeen, 'theme_mode': 'light'});
    await launch(tester);
    expect(Theme.of(tester.element(find.byType(ListenScreen))).brightness, Brightness.dark);
    expect(Theme.of(tester.element(find.byType(ReaderScreen, skipOffstage: false))).brightness, Brightness.light);
    // Settings opened from Taraweeh mode keep its theme.
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness, Brightness.dark);
  });

  testWidgets('light theme renders the same screen', (tester) async {
    h = await Harness.create(prefs: {...introSeen, 'theme_mode': 'light', 'dark_during_taraweeh': false});
    await launch(tester);
    await startListening(tester);
    h.engine.emit(heard(at(93, 3)));
    await settle(tester);
    expect(Theme.of(tester.element(find.byType(ListenScreen))).brightness, Brightness.light);
    expect(currentAyahs(tester), [pos(93, 3).verseId]);
  });

  testWidgets('the introduction shows the first time only; Not now leaves following off', (tester) async {
    h = await Harness.create();
    await launch(tester);
    expect(find.text('Taraweeh mode'), findsOneWidget);
    expect(find.textContaining('Ḥafṣ ʿan ʿĀṣim only'), findsOneWidget);
    expect(find.textContaining('without internet'), findsOneWidget, reason: 'it works offline');
    expect(h.engines, isEmpty, reason: 'nothing starts behind the introduction');
    await tester.ensureVisible(find.text('Not now'));
    await tapAndFinish(tester, find.text('Not now'));
    expect(find.text('Ready to follow'), findsOneWidget);
    expect(h.prefs.getBool('taraweeh_intro_seen'), isTrue);

    await tapAndFinish(tester, find.byTooltip('Back to reading'));
    await tester.tap(taraweehButton);
    await settle(tester);
    expect(find.text('Taraweeh mode'), findsNothing);
    expect(find.text('Getting ready…'), findsOneWidget);
  });

  testWidgets('the introduction\'s Start following starts at once', (tester) async {
    h = await Harness.create();
    await launch(tester);
    final start = find.descendant(of: find.byType(BottomSheet), matching: find.text('Start following'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await settle(tester);
    expect(find.text('Getting ready…'), findsOneWidget);
    expect(h.engines, hasLength(1));
  });

  testWidgets('leaving stops following, keeps the Taraweeh position, and the reading position is untouched',
      (tester) async {
    final container = await launch(tester);
    final reading = container.read(readingPositionProvider);
    await startListening(tester);
    h.engine.emit(heard(at(55, 13)));
    await settle(tester);
    h.engine.emit(heard(at(1, 3))); // Al-Fatiha at the next rakʿah is not where Taraweeh got to
    await settle(tester);

    await tapAndFinish(tester, find.byTooltip('Back to reading'));
    expect(find.byType(ListenScreen), findsNothing);
    expect(container.read(listenControllerProvider).isActive, isFalse);
    expect(h.awake.enabled, isFalse);
    expect(PrefsReadingStore(h.prefs).taraweehPosition()?.verseId, pos(55, 13).verseId);
    expect(container.read(readingPositionProvider), reading);
    expect(PrefsReadingStore(h.prefs).readingPosition(), isNull, reason: 'Taraweeh never writes the reading position');
  });

  testWidgets('the next night starts near where the last one ended, visibly and removably', (tester) async {
    final lastNight = DateTime.now().subtract(const Duration(hours: 22)).toUtc().toIso8601String();
    h = await Harness.create(prefs: {
      ...introSeen,
      'taraweeh_position.v1': '{"v":1,"verse":${pos(5, 81).verseId},"at":"$lastNight"}',
    });
    await launch(tester);
    // 5:82 begins juz 7: the ayah after the last one decides.
    expect(h.engine.startedWith, const JuzHint(7));
    expect(find.text('Tonight: Juz 7'), findsOneWidget);
    expect(find.text("Last night ended at Al-Ma'idah 5:81."), findsOneWidget);

    await tapAndFinish(tester, find.byTooltip('Remove hint'));
    expect(find.text('Tonight: Juz 7'), findsNothing);
    expect(h.engine.startedWith, isNull);
  });

  testWidgets('a session from long ago suggests nothing', (tester) async {
    final old = DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String();
    h = await Harness.create(prefs: {
      ...introSeen,
      'taraweeh_position.v1': '{"v":1,"verse":${pos(5, 81).verseId},"at":"$old"}',
    });
    await launch(tester);
    expect(h.engine.startedWith, isNull);
    expect(find.textContaining('Tonight:'), findsNothing);
  });
}
