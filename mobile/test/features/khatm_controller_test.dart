import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/data/khatm.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/khatm/khatm_controller.dart';

import '../support/fakes.dart';

void main() {
  late Harness h;
  late ProviderContainer c;
  KhatmController khatm() => c.read(khatmProvider.notifier);
  KhatmBook saved() => PrefsReadingStore(h.prefs).khatm();
  Iterable<int> range(int from, int to) => [for (var p = from; p <= to; p++) p];

  Future<void> setUpWith([ReadingStore Function(Harness)? store]) async {
    h = await Harness.create();
    if (store != null) h.readingStore = store(h);
    c = h.container();
    addTearDown(c.dispose);
  }

  ReadingLog on(DateTime day, Iterable<int> pages) => const ReadingLog().adding(day, pages);

  test('start is saved before it is shown', () async {
    await setUpWith();
    expect(await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 42), isTrue);
    final plan = c.read(khatmProvider).active!;
    expect(plan.startedOn, DateTime(2026, 11, 4));
    expect(plan.length, 30);
    expect(plan.nextPage, 42);
    expect(saved().active, plan);
  });

  test('a failed start is reported and shows nothing', () async {
    late FailingStore failing;
    await setUpWith((h) => failing = FailingStore(PrefsReadingStore(h.prefs)));
    expect(await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1), isFalse);
    expect(c.read(khatmProvider).active, isNull);
    failing.failing = false;
    expect(await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1), isTrue);
    expect(c.read(khatmProvider).active, isNotNull);
  });

  test('counted pages join the plan on their own day, saved first; re-reading adds nothing', () async {
    await setUpWith();
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1);
    expect(await khatm().addPages(on(h.now, [1, 2, 3])), isTrue);
    final tomorrow = h.now.add(const Duration(days: 1));
    await khatm().addPages(on(tomorrow, [3, 4]));
    final plan = saved().active!;
    expect(plan.pages, {1: '2026-11-04', 2: '2026-11-04', 3: '2026-11-04', 4: '2026-11-05'});
    expect(c.read(khatmProvider).active, plan);
  });

  test('reading from before the plan began is not part of it', () async {
    await setUpWith();
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1);
    await khatm().addPages(on(DateTime(2026, 11, 3), [1, 2]).adding(h.now, [3]));
    expect(c.read(khatmProvider).active!.pages.keys, [3]);
  });

  test('no plan: counted pages change nothing', () async {
    await setUpWith();
    expect(await khatm().addPages(on(h.now, [1])), isTrue);
    expect(c.read(khatmProvider).active, isNull);
  });

  test('the page map marks pages read today, or unread', () async {
    await setUpWith();
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1);
    await khatm().addPages(on(h.now, [1, 2]));
    expect(await khatm().setRead([2, 3, 4], read: false), isTrue);
    expect(saved().active!.pages.keys, [1]);
    expect(await khatm().setRead([30, 31], read: true), isTrue);
    expect(saved().active!.pages.keys.toSet(), {1, 30, 31});
  });

  test('a correction that cannot be saved changes nothing', () async {
    late FailingStore failing;
    await setUpWith((h) => failing = FailingStore(PrefsReadingStore(h.prefs))..failing = false);
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1);
    failing.failing = true;
    expect(await khatm().setRead([5], read: true), isFalse);
    expect(await khatm().addPages(on(h.now, [6])), isFalse);
    expect(c.read(khatmProvider).active!.read, 0);
  });

  test('change the end date, then stop', () async {
    await setUpWith();
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1);
    await khatm().addPages(on(h.now, [1, 2]));
    expect(await khatm().changeEnd(DateTime(2026, 11, 18)), isTrue);
    expect(saved().active!.endsOn, DateTime(2026, 11, 18));
    expect(saved().active!.read, 2, reason: 'the pages stay with the plan');
    expect(await khatm().changeEnd(DateTime(2026, 1, 1)), isTrue);
    expect(c.read(khatmProvider).active!.endsOn, DateTime(2026, 11, 4), reason: 'never before today');
    expect(await khatm().stop(), isTrue);
    expect(c.read(khatmProvider).active, isNull);
    expect(saved().active, isNull);
  });

  test('the last page completes the khatm, from reading or from the map', () async {
    await setUpWith();
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 300);
    await khatm().addPages(on(h.now, range(1, 600)));
    h.now = DateTime(2026, 11, 20, 9);
    await khatm().addPages(on(h.now, [601, 602]));
    expect(c.read(khatmProvider).active!.remaining, 2);
    await khatm().setRead([603, 604], read: true);
    final book = c.read(khatmProvider);
    expect(book.active, isNull);
    expect(book.finished.single.startedOn, DateTime(2026, 11, 4));
    expect(book.finished.single.completedOn, DateTime(2026, 11, 20));
    expect(book.finished.single.days, 17);
    expect(saved().finished, book.finished);

    // A second khatm keeps the first.
    await khatm().start(endsOn: DateTime(2026, 12, 20), startPage: 1);
    expect(saved().finished, hasLength(1));
  });

  test('changes made one right after another all land, in order', () async {
    await setUpWith();
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1);
    final a = khatm().setRead([1], read: true);
    final b = khatm().setRead([2], read: true);
    final d = khatm().setRead([1], read: false);
    expect(await Future.wait([a, b, d]), [true, true, true]);
    expect(saved().active!.pages.keys, [2]);
  });
}
