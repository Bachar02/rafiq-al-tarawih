import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/app.dart';
import 'package:rafiq/features/adhkar/adhkar_screen.dart';
import 'package:rafiq/features/adhkar/dhikr_reminders.dart';
import 'package:rafiq/services/reminders.dart';

import '../support/app_nav.dart';
import '../support/fakes.dart';

void main() {
  group('when', () {
    test('every 2 hours from 8:00 to 22:00, for two weeks, after now', () {
      final times = dhikrTimes(now: DateTime(2026, 11, 4, 9, 30), everyHours: 2);
      expect(times.take(8), [
        for (final h in [10, 12, 14, 16, 18, 20, 22]) DateTime(2026, 11, 4, h),
        DateTime(2026, 11, 5, 8),
      ]);
      expect(times, hasLength(7 + 13 * 8));
      expect(times.last, DateTime(2026, 11, 17, 22));
      expect(times.every((t) => t.hour >= 8 && t.hour <= 22), isTrue, reason: 'never in the night');
    });

    test('every hour, 3 hours and 4 hours', () {
      final day = DateTime(2026, 11, 4, 7);
      List<int> hours(int every) => [
            for (final t in dhikrTimes(now: day, everyHours: every))
              if (t.day == 4) t.hour
          ];
      expect(hours(1), [for (var h = 8; h <= 22; h++) h]);
      expect(hours(3), [8, 11, 14, 17, 20]);
      expect(hours(4), [8, 12, 16, 20]);
    });

    test('quiet until a time: none before it', () {
      final times = dhikrTimes(
        now: DateTime(2026, 11, 4, 19, 50),
        everyHours: 2,
        quietUntil: DateTime(2026, 11, 4, 22, 50),
      );
      expect(times.first, DateTime(2026, 11, 5, 8));
    });

    test('across a change of clocks, still on the hour, local time', () {
      // 29 March 2026: clocks go forward in much of Europe.
      final times = dhikrTimes(now: DateTime(2026, 3, 28, 23), everyHours: 2);
      expect(times.where((t) => t.day == 29).map((t) => t.hour), [8, 10, 12, 14, 16, 18, 20, 22]);
    });

    test('each hour has its own id for the whole window, and keeps it', () {
      final times = dhikrTimes(now: DateTime(2026, 11, 4, 7), everyHours: 1);
      final ids = times.map(dhikrNotificationId).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.every((id) => id >= dhikrIdBase && id < dhikrIdBase + dhikrIdCycle), isTrue);
      expect(dhikrNotificationId(DateTime(2026, 11, 4, 10)), dhikrNotificationId(DateTime(2026, 11, 4, 10, 0)));
    });

    test('the pick is the same for the same hour, and spread over the adhkar', () {
      final times = dhikrTimes(now: DateTime(2026, 11, 4, 7), everyHours: 1);
      expect([for (final t in times) dhikrPick(t, 16)], [for (final t in times) dhikrPick(t, 16)]);
      expect({for (final t in times) dhikrPick(t, 16)}, hasLength(16), reason: 'all of them come up');
    });
  });

  group('the setting', () {
    late Harness h;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> launch(WidgetTester tester, [Map<String, Object> prefs = const {}]) async {
      h = await Harness.create(prefs: {'taraweeh_intro_seen': true, ...prefs});
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const RafiqApp()));
      await settle(tester);
    }

    Future<void> openAdhkar(WidgetTester tester) async {
      await tapNav(tester, 'More');
      await tester.tap(find.text('Adhkar'));
      await settle(tester);
      await tester.ensureVisible(find.text('Dhikr reminders').last);
      await settle(tester);
    }

    testWidgets('off until turned on; nothing is touched meanwhile', (tester) async {
      await launch(tester);
      expect(h.reminders.dhikrReplaced, 0);
      await openAdhkar(tester);
      expect(
        find.text('A short dhikr at the top of the screen now and then, even when Rafiq is closed'),
        findsOneWidget,
      );
      expect(find.text('How often'), findsNothing);
    });

    testWidgets('turned on: on the screen, two weeks of adhkar, each with its meaning', (tester) async {
      await launch(tester); // Wednesday 4 November, 20:00
      await openAdhkar(tester);
      await tester.tap(find.text('Dhikr reminders').last);
      await settle(tester);
      // Android's "Appear on top" first, explained.
      expect(find.textContaining('small card at the top right of the screen, over other apps'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(h.reminders.onScreenAsked, 1);
      expect(h.reminders.asked, 0, reason: 'the card needs no notification permission');
      expect(h.prefs.getBool('dhikr_reminders_on'), isTrue);
      await tester.ensureVisible(find.text('On the screen'));
      await settle(tester);
      expect(find.text('A small card at the top right, until you tap it'), findsOneWidget);
      expect(h.reminders.closeLabel, 'Tap to close');
      expect(find.text('Dhikr reminders on'), findsOneWidget);
      expect(find.text('Every 2 hours, from 8:00 AM to 10:00 PM'), findsOneWidget);
      final dhikr = h.reminders.dhikr;
      expect(dhikr.first.at, DateTime(2026, 11, 4, 22), reason: '20:00 is not ahead');
      expect(dhikr, hasLength(1 + 13 * 8));
      expect(h.reminders.dhikrChannel, 'Dhikr reminders');
      expect(dhikr.first.title, 'Remember Allah');
      final pool = loadAdhkar().forNotifications;
      for (final r in dhikr) {
        // Collapsed, the Arabic alone (mixed with English on one line it
        // reads in the wrong order); expanded, its meaning under it.
        final shown = pool.firstWhere((d) => d.arabic == r.body);
        expect(r.expanded, '${shown.arabic}\n${shown.meaning('en')}');
      }
      for (var i = 1; i < dhikr.length; i++) {
        expect(dhikr[i].body, isNot(dhikr[i - 1].body), reason: 'never twice in a row');
      }
      expect(h.reminders.scheduled, isEmpty, reason: 'the reading reminder is apart');
    });

    testWidgets('every hour instead: rescheduled; in Arabic, the words alone', (tester) async {
      await launch(tester, {'dhikr_reminders_on': true, 'language': 'ar'});
      expect(h.reminders.dhikr, hasLength(1 + 13 * 8), reason: 'scheduled when the app opens');
      expect(h.reminders.dhikr.first.title, 'اذكر الله');
      expect(h.reminders.dhikr.first.expanded, isNull, reason: 'no meaning: the words are Arabic');
      await tapNav(tester, 'المزيد');
      await tester.tap(find.text('الأذكار'));
      await settle(tester);
      await tester.ensureVisible(find.text('كم مرة'));
      await settle(tester);
      await tester.tap(find.text('كم مرة'));
      await settle(tester);
      await tester.tap(find.text('كل ساعة'));
      await settle(tester);
      expect(h.prefs.getInt('dhikr_every_hours'), 1);
      expect(h.reminders.dhikr, hasLength(2 + 13 * 15), reason: '21:00 and 22:00 today, then 15 a day');
    });

    testWidgets('allowed on the screen already: nothing asked, on at once', (tester) async {
      await launch(tester);
      h.reminders.onScreen = true;
      await openAdhkar(tester);
      await tester.tap(find.text('Dhikr reminders').last);
      await settle(tester);
      expect(find.text('Continue'), findsNothing);
      expect(h.reminders.onScreenAsked, 0);
      expect(h.reminders.asked, 0);
      expect(h.prefs.getBool('dhikr_reminders_on'), isTrue);
      expect(h.reminders.dhikr, isNotEmpty);
    });

    testWidgets('notifications instead: permission to notify, then on; the card can be allowed later', (tester) async {
      await launch(tester);
      await openAdhkar(tester);
      await tester.tap(find.text('Dhikr reminders').last);
      await settle(tester);
      await tester.tap(find.text('Use notifications instead'));
      await settle(tester);
      expect(h.reminders.onScreenAsked, 0);
      expect(h.reminders.asked, 1);
      expect(h.prefs.getBool('dhikr_reminders_on'), isTrue);
      await tester.ensureVisible(find.text('On the screen'));
      await settle(tester);
      expect(find.text('Not allowed: each dhikr waits in the notifications'), findsOneWidget);
      await tester.tap(find.text('On the screen'));
      await settle(tester);
      expect(h.reminders.onScreenAsked, 1);
      expect(find.text('A small card at the top right, until you tap it'), findsOneWidget);
    });

    testWidgets('the card taken back later: permission to notify asked then', (tester) async {
      await launch(tester, {'dhikr_reminders_on': true});
      h.reminders.onScreen = true;
      h.reminders.grantOnScreen = false;
      await openAdhkar(tester);
      await tester.ensureVisible(find.text('On the screen'));
      await settle(tester);
      expect(find.text('A small card at the top right, until you tap it'), findsOneWidget);
      await tester.tap(find.text('On the screen'));
      await settle(tester);
      expect(h.reminders.onScreenAsked, 1);
      expect(h.reminders.asked, 1, reason: 'each dhikr is a notification now');
      expect(find.text('Not allowed: each dhikr waits in the notifications'), findsOneWidget);
    });

    testWidgets('the setting refused on the phone: notifications, then', (tester) async {
      await launch(tester);
      h.reminders.grantOnScreen = false;
      await openAdhkar(tester);
      await tester.tap(find.text('Dhikr reminders').last);
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(h.reminders.onScreenAsked, 1);
      expect(h.reminders.asked, 1);
      expect(h.prefs.getBool('dhikr_reminders_on'), isTrue);
    });

    testWidgets('neither allowed: stays off, says where to turn notifications on', (tester) async {
      await launch(tester);
      h.reminders.allow = false;
      h.reminders.grantOnScreen = false;
      await openAdhkar(tester);
      await tester.tap(find.text('Dhikr reminders').last);
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(h.prefs.getBool('dhikr_reminders_on') ?? false, isFalse);
      expect(h.reminders.dhikr, isEmpty);
      expect(find.textContaining('Notifications are off for Rafiq'), findsOneWidget);
    });

    testWidgets('show one now: the dhikr this hour brings, the way they come', (tester) async {
      await launch(tester, {'dhikr_reminders_on': true});
      await openAdhkar(tester);
      await tester.ensureVisible(find.text('Show one now'));
      await settle(tester);
      await tester.tap(find.text('Show one now'));
      await settle(tester);
      final shown = h.reminders.dhikrShown.single;
      final pool = loadAdhkar().forNotifications;
      expect(shown.body, pool[dhikrPick(h.now, pool.length)].arabic);
      expect(shown.title, 'Remember Allah');
    });

    testWidgets('turned off: every one cancelled, the reading reminder kept', (tester) async {
      await launch(tester, {'dhikr_reminders_on': true, 'reminder_on': true});
      expect(h.reminders.dhikr, isNotEmpty);
      expect(h.reminders.scheduled, hasLength(7));
      await openAdhkar(tester);
      await tester.tap(find.text('Dhikr reminders').last);
      await settle(tester);
      expect(h.prefs.getBool('dhikr_reminders_on'), isFalse);
      expect(h.reminders.dhikr, isEmpty);
      expect(h.reminders.scheduled, hasLength(7));
    });

    testWidgets('in Settings too', (tester) async {
      await launch(tester);
      await openSettings(tester);
      await tester.scrollUntilVisible(find.text('Dhikr reminders').last, 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('DHIKR REMINDERS'), findsOneWidget, reason: 'its own group');
    });

    testWidgets('Taraweeh mode keeps them away for 3 hours, then they come back', (tester) async {
      await launch(tester, {'dhikr_reminders_on': true});
      expect(h.reminders.dhikr.first.at, DateTime(2026, 11, 4, 22));
      await tester.tap(taraweehButton);
      await settle(tester);
      expect(h.reminders.dhikr.first.at, DateTime(2026, 11, 5, 8), reason: 'nothing over the imam at 22:00');
      await tester.tap(find.byTooltip('Back to reading'));
      await settle(tester);
      expect(h.reminders.dhikr.first.at, DateTime(2026, 11, 4, 22));
    });

    testWidgets('a tapped dhikr opens the adhkar', (tester) async {
      await launch(tester, {'dhikr_reminders_on': true});
      h.reminders.tap(dhikrPayload);
      await settle(tester);
      expect(find.byType(AdhkarScreen), findsOneWidget);
      h.reminders.tap('something else');
      await settle(tester);
      expect(find.byType(AdhkarScreen), findsOneWidget, reason: 'one screen, not two');
    });
  });
}
