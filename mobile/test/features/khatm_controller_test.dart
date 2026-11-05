import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rafiq/app/providers.dart';
import 'package:rafiq/data/khatm.dart';
import 'package:rafiq/data/reading_store.dart';
import 'package:rafiq/features/khatm/khatm_controller.dart';
import 'package:rafiq/features/reader/reading_progress.dart';

import '../support/fakes.dart';

void main() {
  late Harness h;
  late ProviderContainer c;
  KhatmController khatm() => c.read(khatmProvider.notifier);
  ReadingProgressController progress() => c.read(readingProgressProvider.notifier);
  KhatmBook saved() => PrefsReadingStore(h.prefs).khatm();

  Future<void> setUpWith([ReadingStore Function(Harness)? store]) async {
    h = await Harness.create();
    if (store != null) h.readingStore = store(h);
    c = h.container();
    addTearDown(c.dispose);
  }

  /// Read forward from [from] to [to], a page at a time, as the reader does.
  void readOn(int from, int to) {
    progress().jumpedTo(from);
    for (var p = from + 1; p <= to; p++) {
      progress().movedTo(p);
    }
  }

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

  test('pages read count once, from the reading rule; jumps count nothing', () async {
    await setUpWith();
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1);
    readOn(1, 4); // pages 1, 2, 3 read
    expect(c.read(khatmProvider).active!.read, 3);
    readOn(1, 4); // again: nothing new
    progress().jumpedTo(300); // a jump
    progress().movedTo(400); // a leap
    final plan = c.read(khatmProvider).active!;
    expect(plan.pages.keys.toSet(), {1, 2, 3});
    expect(plan.readOn(h.now), 3);
    expect(plan.todayTarget(h.now), 21);
  });

  test('no plan: reading records nothing', () async {
    await setUpWith();
    readOn(1, 5);
    expect(c.read(khatmProvider).active, isNull);
    expect(progress().today, 4);
  });

  test('pages are saved a moment later, and on flush', () async {
    await setUpWith();
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1);
    readOn(1, 3);
    expect(saved().active!.read, 0, reason: 'not yet');
    expect(await khatm().flush(), isTrue);
    expect(saved().active!.read, 2);
  });

  test('a failed save of pages stays pending and is retried', () async {
    late FailingStore failing;
    await setUpWith((h) => failing = FailingStore(PrefsReadingStore(h.prefs)));
    failing.failing = false;
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1);
    failing.failing = true;
    readOn(1, 3);
    expect(await khatm().flush(), isFalse);
    expect(c.read(khatmProvider).active!.read, 2, reason: 'still shown, still pending');
    failing.failing = false;
    expect(await khatm().flush(), isTrue);
    expect(saved().active!.read, 2);
  });

  test('change the end date, then stop; nothing pending is written back', () async {
    await setUpWith();
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1);
    readOn(1, 3);
    expect(await khatm().changeEnd(DateTime(2026, 11, 18)), isTrue);
    expect(saved().active!.endsOn, DateTime(2026, 11, 18));
    expect(saved().active!.read, 2, reason: 'the pages went with the change');
    expect(await khatm().changeEnd(DateTime(2026, 1, 1)), isTrue);
    expect(c.read(khatmProvider).active!.endsOn, DateTime(2026, 11, 4), reason: 'never before today');

    readOn(3, 5);
    expect(await khatm().stop(), isTrue);
    await khatm().flush();
    expect(c.read(khatmProvider).active, isNull);
    expect(saved().active, isNull);
  });

  test('the last page completes the khatm: it moves to finished', () async {
    await setUpWith();
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 300);
    // Everything but the start page's neighbourhood, read on earlier days.
    readOn(300, 604);
    readOn(1, 297);
    h.now = DateTime(2026, 11, 20, 9);
    expect(c.read(khatmProvider).active!.remaining, 3);
    readOn(297, 300); // 297, 298, 299: the last pages
    final book = c.read(khatmProvider);
    expect(book.active, isNull);
    expect(book.finished.single.startedOn, DateTime(2026, 11, 4));
    expect(book.finished.single.completedOn, DateTime(2026, 11, 20));
    expect(book.finished.single.days, 17);
    await khatm().flush();
    expect(saved().finished, book.finished);

    // A second khatm keeps the first.
    await khatm().start(endsOn: DateTime(2026, 12, 20), startPage: 1);
    expect(saved().finished, hasLength(1));
  });

  test('a plan restored after a restart goes on where it was', () async {
    await setUpWith();
    await khatm().start(endsOn: DateTime(2026, 12, 3), startPage: 1);
    readOn(1, 6);
    c.dispose(); // the app is closed: pending pages are written
    await pumpEventQueue();
    c = h.container();
    addTearDown(c.dispose);
    expect(c.read(khatmProvider).active!.read, 5);
    expect(c.read(khatmProvider).active!.nextPage, 6);
  });
}
