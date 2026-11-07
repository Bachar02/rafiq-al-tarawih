import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/progress/progress_screen.dart';
import 'package:rafiq/features/progress/reading_grid.dart';

import '../support/app_nav.dart';
import '../support/fakes.dart';

void main() {
  late Harness h;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Two days read before today (Wednesday 4 November 2026): 3 and 6 pages.
  const history = {'reading_log.v1': '{"v":1,"days":{"2026-11-02":[1,2,3],"2026-11-03":[4,5,6,7,8,9]}}'};

  Future<void> launch(WidgetTester tester, [Map<String, Object> prefs = const {}, DateTime? now]) async {
    h = await Harness.create(prefs: {'taraweeh_intro_seen': true, ...prefs});
    if (now != null) h.now = now;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
    await settle(tester);
  }

  Future<void> openReading(WidgetTester tester) async {
    await tapNav(tester, 'Bookmarks');
    await tester.tap(find.byType(ReadingCard));
    await settle(tester);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(RafiqApp)));

  group('the chart', () {
    testWidgets('the Bookmarks card shows the run and the year, and opens the Reading screen', (tester) async {
      await launch(tester, history);
      await tapNav(tester, 'Bookmarks');
      expect(find.text('Your reading'), findsOneWidget);
      expect(find.text('2 days in a row'), findsOneWidget, reason: 'today not read yet does not end it');
      expect(find.text('2 days read this year'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Your reading. 2 days in a row')), findsOneWidget);

      await tester.tap(find.byType(ReadingCard));
      await settle(tester);
      expect(find.byType(ProgressScreen), findsOneWidget);
      expect(find.text('2 days in a row'), findsOneWidget);
      expect(find.text('Best: 2 days'), findsOneWidget);
      expect(find.text('Wed, Nov 4: 0 pages'), findsOneWidget, reason: 'today, until another day is tapped');
    });

    testWidgets('a tapped day says its pages; the last 7 days and the totals', (tester) async {
      await launch(tester, history);
      await openReading(tester);
      tester.widget<ReadingGrid>(find.byType(ReadingGrid)).onDay!(DateTime(2026, 11, 3));
      await settle(tester);
      expect(find.text('Tue, Nov 3: 6 pages'), findsOneWidget);
      // Each bar is one item for a screen reader.
      expect(find.bySemanticsLabel('Mon, Nov 2: 3 pages'), findsOneWidget);
      expect(find.bySemanticsLabel('Fri, Oct 30: 0 pages'), findsOneWidget);
      await tester.ensureVisible(find.text('Pages this month'));
      await settle(tester);
      expect(find.text('9'), findsOneWidget);
      await tester.ensureVisible(find.text('Al-Bukhari and Muslim'));
      expect(find.textContaining('most consistent'), findsOneWidget);
    });

    testWidgets('nothing read yet: an invitation, not a zero', (tester) async {
      await launch(tester);
      await tapNav(tester, 'Bookmarks');
      expect(find.text('Read a page today to start.'), findsOneWidget);
      expect(find.text('No days read yet this year'), findsOneWidget);
    });

    testWidgets('pages waiting for review count today, as in the reader bar', (tester) async {
      await launch(tester, {...history, 'reading_pending.v1': '{"v":1,"days":{"2026-11-04":[10,11]}}'});
      await tester.tap(find.text('Not now'));
      await settle(tester);
      await tapNav(tester, 'Bookmarks');
      expect(find.text('3 days in a row'), findsOneWidget);
    });

    testWidgets('the goal is drawn and named under the last 7 days', (tester) async {
      await launch(tester, {...history, 'daily_goal_pages': 5});
      await openReading(tester);
      expect(find.text('Daily reading goal: 5 pages'), findsOneWidget);
    });
  });

  group('the daily reminder', () {
    testWidgets('turned on: permission asked, a week of reminders, the text says where to continue', (tester) async {
      await launch(tester, {'daily_goal_pages': 10}, DateTime(2026, 11, 4, 9));
      await openReading(tester);
      await tester.ensureVisible(find.text('Daily reminder').last);
      await settle(tester);
      await tester.tap(find.text('Daily reminder').last);
      await settle(tester);
      expect(h.reminders.asked, 1);
      expect(h.prefs.getBool('reminder_on'), isTrue);
      expect(h.reminders.scheduled, hasLength(7));
      expect(h.reminders.scheduled.first.at, DateTime(2026, 11, 4, 20), reason: 'today: not read, and 20:00 is ahead');
      expect(h.reminders.scheduled.first.title, 'Your daily reading');
      expect(h.reminders.scheduled.first.body, '10 pages today. Continue at Al-Fatiha, page 1.');
      expect(h.reminders.channel, 'Daily reading reminder');
      expect(find.text('Reminder set for 8:00 PM'), findsOneWidget);
      expect(find.text('Around 8:00 PM, on days you haven’t read yet'), findsOneWidget);
      expect(find.text('Reminder time'), findsOneWidget);
    });

    testWidgets('notifications refused: it stays off and says where to turn them on', (tester) async {
      await launch(tester);
      h.reminders.allow = false;
      await openReading(tester);
      await tester.ensureVisible(find.text('Daily reminder').last);
      await settle(tester);
      await tester.tap(find.text('Daily reminder').last);
      await settle(tester);
      expect(h.prefs.getBool('reminder_on') ?? false, isFalse);
      expect(h.reminders.scheduled, isEmpty);
      expect(find.textContaining('Notifications are off for Rafiq'), findsOneWidget);
    });

    testWidgets('turned off: every reminder is cancelled', (tester) async {
      await launch(tester, {'reminder_on': true}, DateTime(2026, 11, 4, 9));
      expect(h.reminders.scheduled, hasLength(7), reason: 'scheduled when the app opens');
      await openReading(tester);
      await tester.ensureVisible(find.text('Daily reminder').last);
      await settle(tester);
      await tester.tap(find.text('Daily reminder').last);
      await settle(tester);
      expect(h.prefs.getBool('reminder_on'), isFalse);
      expect(h.reminders.scheduled, isEmpty);
    });

    testWidgets('off and never turned on: the notification system is left alone', (tester) async {
      await launch(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await settle(tester);
      expect(h.reminders.replaced, 0);
      expect(h.reminders.asked, 0);
    });

    testWidgets('reading today moves the next reminder to tomorrow when the app is hidden', (tester) async {
      await launch(tester, {'reminder_on': true}, DateTime(2026, 11, 4, 9));
      expect(h.reminders.scheduled.first.at, DateTime(2026, 11, 4, 20));
      await container(tester).read(readingProgressProvider.notifier).add(
            ReadingLog({
              '2026-11-04': {42},
            }),
          );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await settle(tester);
      expect(h.reminders.scheduled.first.at, DateTime(2026, 11, 5, 20));
      expect(h.reminders.scheduled.first.body, 'Continue at Al-Fatiha, page 1.');
    });

    testWidgets('a khatm sets the day\'s target and where to continue', (tester) async {
      await launch(tester, {'reminder_on': true}, DateTime(2026, 11, 4, 9));
      await tapNav(tester, 'More');
      await tester.tap(find.text('Khatm planner'));
      await settle(tester);
      await tester.ensureVisible(find.text('Start khatm'));
      await settle(tester);
      await tester.tap(find.text('Start khatm'));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
      // The chart's goal line is the khatm's target, and says so.
      await openReading(tester);
      expect(find.textContaining(RegExp(r'^Khatm today: \d+ pages$')), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await settle(tester);
      expect(h.reminders.scheduled.first.body, matches(RegExp(r'^\d+ pages today\. Continue at Al-Fatiha, page 1\.$')));
    });

    testWidgets('in Settings too', (tester) async {
      await launch(tester);
      await openSettings(tester);
      expect(find.text('DAILY REMINDER'), findsOneWidget);
      expect(find.text('A notification on days you haven’t read yet'), findsOneWidget);
    });

    group('offered once, after the first counted reading', () {
      const pending = {'reading_pending.v1': '{"v":1,"days":{"2026-11-03":[40,41]}}'};

      testWidgets('Remind me turns it on', (tester) async {
        await launch(tester, pending, DateTime(2026, 11, 4, 9));
        await tester.tap(find.text('Count 2 pages'));
        await settle(tester);
        expect(find.text('A daily reminder?'), findsOneWidget);
        await tester.tap(find.text('Remind me at 8:00 PM'));
        await settle(tester);
        expect(h.prefs.getBool('reminder_on'), isTrue);
        expect(h.reminders.scheduled, hasLength(7));
      });

      testWidgets('Not now: never offered again', (tester) async {
        await launch(tester, pending);
        await tester.tap(find.text('Count 2 pages'));
        await settle(tester);
        await tester.tap(find.text('Not now'));
        await settle(tester);
        expect(h.prefs.getBool('reminder_on') ?? false, isFalse);
        expect(h.prefs.getBool('reminder_offered'), isTrue);
        expect(h.reminders.asked, 0);
      });

      testWidgets('not offered when nothing was counted', (tester) async {
        await launch(tester, pending);
        await tester.tap(find.text('Don’t count these'));
        await settle(tester);
        expect(find.text('A daily reminder?'), findsNothing);
        expect(h.prefs.getBool('reminder_offered') ?? false, isFalse);
      });
    });
  });
}
