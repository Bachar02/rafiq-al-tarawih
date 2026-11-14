import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/app_scope.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/data/backup.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/reader/reader_screen.dart';
import 'package:rafiq/features/settings/settings_screen.dart';

import '../support/app_nav.dart';
import '../support/fakes.dart';

void main() {
  final quran = loadQuran();
  late Harness h;

  /// The app as main.dart builds it: in a scope a restore can open again.
  Future<void> launch(WidgetTester tester, Map<String, Object> prefs) async {
    h = await Harness.create(prefs: {'taraweeh_intro_seen': true, ...prefs});
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppScope(overrides: h.overrides, child: const RafiqApp()));
    await tester.pumpAndSettle();
  }

  Future<void> tapInSettings(WidgetTester tester, String text) async {
    await openSettings(tester);
    await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Map<String, Object?> stored() => {for (final k in h.prefs.getKeys()) k: h.prefs.get(k)};

  String position(int verseId) =>
      jsonEncode(SavedPosition(verseId: verseId, savedAt: DateTime.utc(2026, 10, 1)).toJson());

  testWidgets('saved: everything stored, in a file named by the day', (tester) async {
    await launch(tester, {'dhikr_reminders_on': true, PrefsReadingStore.readingKey: position(262)});
    await tapInSettings(tester, 'Save a backup');
    expect(find.text('Backup saved'), findsOneWidget);
    final file = h.backupFiles.saved['rafiq-backup-2026-11-04.json']!;
    final backup = Backup.decode(file);
    expect(backup.values['dhikr_reminders_on'], true);
    expect(backup.values.keys, containsAll(h.prefs.getKeys()));
  });

  testWidgets('the "Save to" screen cancelled: nothing said', (tester) async {
    await launch(tester, {});
    h.backupFiles.cancelSave = true;
    await tapInSettings(tester, 'Save a backup');
    expect(find.text('Backup saved'), findsNothing);
    expect(h.backupFiles.saved, isEmpty);
  });

  testWidgets('restored: the backup replaces everything, the app opens again from it', (tester) async {
    await launch(tester, {'dhikr_reminders_on': true, PrefsReadingStore.readingKey: position(1000)});
    expect(h.reminders.dhikr.isOff, isFalse);
    final ayatAlKursi = quran.verseId(2, 255)!;
    final values = <String, Object>{
      'taraweeh_intro_seen': true,
      'reminder_on': true,
      PrefsReadingStore.readingKey: position(ayatAlKursi),
    };
    h.backupFiles.picked = Backup(createdAt: DateTime(2026, 11, 1, 9, 30), values: values).encode();
    await tapInSettings(tester, 'Restore a backup');
    // intl puts a narrow no-break space before AM.
    expect(find.textContaining(RegExp(r'^Restore the backup of November 1, 2026 9:30\sAM\?$')), findsOneWidget);
    expect(find.textContaining('Everything Rafiq holds on this phone is replaced'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(stored(), values);
    expect(find.byType(SettingsScreen), findsNothing, reason: 'the app opened again');
    expect(find.text('Backup restored'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(ReaderScreen)));
    expect(container.read(readingPositionProvider), ayatAlKursi);
    expect(container.read(settingsProvider).dhikrRemindersOn, isFalse);
    // The reminders follow the backup, not what this phone had scheduled.
    expect(h.reminders.dhikr.isOff, isTrue);
    expect(h.reminders.scheduled, hasLength(7));
  });

  testWidgets('cancelled at the question: nothing changes', (tester) async {
    await launch(tester, {'dhikr_reminders_on': true});
    final before = stored();
    h.backupFiles.picked = Backup(createdAt: DateTime(2026, 11, 1), values: const {'x': 1}).encode();
    await tapInSettings(tester, 'Restore a backup');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(stored(), before);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('not a backup, or from a newer Rafiq: said so, nothing touched', (tester) async {
    await launch(tester, {'dhikr_reminders_on': true});
    final before = stored();
    h.backupFiles.picked = '{"some": "other file"}';
    await tapInSettings(tester, 'Restore a backup');
    expect(find.text('This file is not a Rafiq backup.'), findsOneWidget);
    expect(find.text('Restore'), findsNothing, reason: 'nothing to ask');
    ScaffoldMessenger.of(tester.element(find.byType(SettingsScreen))).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    h.backupFiles.picked = '{"format":"rafiq-backup","v":9,"created":"2027-01-01T00:00:00Z","values":{}}';
    await tester.scrollUntilVisible(find.text('Restore a backup'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Restore a backup'));
    await tester.pumpAndSettle();
    expect(find.text('This backup comes from a newer Rafiq. Update Rafiq, then try again.'), findsOneWidget);
    expect(stored(), before);
  });
}
