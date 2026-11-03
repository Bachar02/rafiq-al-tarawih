import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/core/recognition/models.dart';
import 'package:rafiq/features/listen/listen_screen.dart';
import 'package:rafiq/services/server_health.dart';

import '../support/fakes.dart';

void main() {
  late Harness h;

  Future<ProviderContainer> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(ListenScreen)));
  }

  /// Settle animations without waiting on indeterminate spinners forever.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() async => h = await Harness.create());

  testWidgets('idle: invites the user to start', (tester) async {
    await launch(tester);
    expect(find.text('Ready to follow'), findsOneWidget);
    expect(find.bySemanticsLabel('Start following the imam'), findsOneWidget);
  });

  testWidgets('tap the mic: connects, then follows the imam with the ayah highlighted', (tester) async {
    await launch(tester);
    await tester.tap(find.bySemanticsLabel('Start following the imam'));
    await settle(tester);
    expect(find.text('Connecting…'), findsWidgets);

    h.engine.emit(const EngineReady());
    await settle(tester);
    expect(find.text('Listening…'), findsOneWidget);

    h.engine.emit(heard(at(93, 3)));
    await settle(tester);
    expect(find.text('Ad-Dhuhaa'), findsOneWidget);
    expect(find.textContaining('Ayah 3 of 11'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    final highlighted = find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true);
    expect(highlighted, findsOneWidget);
    expect((tester.widget(highlighted) as Semantics).properties.label, 'Ayah 3');
    expect(find.bySemanticsLabel('Stop following'), findsOneWidget);
  });

  testWidgets('ambiguous text shows the alternatives', (tester) async {
    await launch(tester);
    await tester.tap(find.bySemanticsLabel('Start following the imam'));
    await settle(tester);
    h.engine.emit(const EngineReady());
    h.engine.emit(heard(TrackState(
      position: pos(26, 109),
      status: TrackStatus.uncertain,
      alternatives: [pos(26, 127), pos(26, 145)],
    )));
    await settle(tester);
    expect(find.textContaining('could also be 26:127 · 26:145'), findsOneWidget);
    expect(find.text('Not sure'), findsOneWidget);
  });

  testWidgets('a first guess is offered as a maybe, not as fact', (tester) async {
    await launch(tester);
    await tester.tap(find.bySemanticsLabel('Start following the imam'));
    await settle(tester);
    h.engine.emit(const EngineReady());
    h.engine.emit(heard(TrackState(status: TrackStatus.uncertain, pending: pos(7, 29)), isFinal: false));
    await settle(tester);
    expect(find.textContaining('Maybe Al-A'), findsOneWidget);
    expect(find.text('Listening…'), findsOneWidget);
  });

  testWidgets('unreachable server: explains and links to settings', (tester) async {
    await launch(tester);
    await tester.tap(find.bySemanticsLabel('Start following the imam'));
    await settle(tester);
    h.engine.emit(
        const EngineFailure('Cannot reach the recognition server at 10.0.2.2:8765', kind: FailureKind.unreachable));
    await settle(tester);
    expect(find.text('Cannot reach the server'), findsOneWidget);
    expect(find.text('Server settings'), findsOneWidget);
    await tester.ensureVisible(find.text('Server settings'));
    await tester.tap(find.text('Server settings'));
    await settle(tester);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('denied microphone: explains how to allow it', (tester) async {
    h.audio.permission = false;
    await launch(tester);
    await tester.tap(find.bySemanticsLabel('Start following the imam'));
    await settle(tester);
    expect(find.text('Microphone access needed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('hint sheet: pick a juz, see the chip, clear it', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Help the app (hint)'));
    await settle(tester);
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
    await tester.tap(find.text('Test connection'));
    await settle(tester);
    expect(find.textContaining('Connected · 12 ms · speech model cuda'), findsOneWidget);

    h.health = const ServerHealth.failed('Cannot reach the server. Is it running, and on the same Wi-Fi?');
    await tester.tap(find.text('Test connection'));
    await settle(tester);
    expect(find.textContaining('same Wi-Fi'), findsOneWidget);
  });

  testWidgets('settings: an invalid address is rejected and not saved', (tester) async {
    await launch(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Test connection'));
    await settle(tester);
    expect(find.textContaining('Enter the address'), findsOneWidget);
    expect(h.prefs.getString('server_address'), isNull);
  });
}
