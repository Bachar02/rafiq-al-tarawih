/// Moving around the app the way a user does, for widget tests.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tap a destination of the bottom bar by its label (Read, Surahs, ...).
Future<void> tapNav(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

/// More → Settings.
Future<void> openSettings(WidgetTester tester, {String more = 'More', String settings = 'Settings'}) async {
  await tapNav(tester, more);
  await tester.ensureVisible(find.text(settings)); // below the fold at 200% text
  await tester.pumpAndSettle();
  await tester.tap(find.text(settings));
  await tester.pumpAndSettle();
}

/// The bottom bar's Taraweeh button (in any language).
Finder get taraweehButton => find.descendant(of: find.byType(NavigationBar), matching: find.byIcon(Icons.mic_none));
