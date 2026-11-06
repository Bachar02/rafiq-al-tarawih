import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/khatm.dart';
import '../../data/reading_store.dart';

/// The khatm plan: one active plan at most, and the finished ones.
///
/// Every change is saved before it is shown, so the screen never claims a
/// plan or a page the app has not kept. Pages arrive two ways: a reading
/// session the user counted ([addPages], the same pages as the daily log),
/// and the page map, where the user marks pages read or unread himself
/// ([setRead]), for a mistake or a paper mushaf. Covering all 604 pages
/// completes the khatm: it moves to the finished list.
class KhatmController extends Notifier<KhatmBook> {
  late ReadingStore _store;
  late DateTime Function() _now;

  /// Changes run one after another, each on the book the last one saved.
  Future<void> _saving = Future.value();

  @override
  KhatmBook build() {
    _store = ref.read(readingStoreProvider);
    _now = ref.read(clockProvider);
    return _store.khatm();
  }

  DateTime get _today => dateOnly(_now());

  KhatmPlan? get active => state.active;

  /// Start a plan ending on [endsOn] (inclusive), reading from [startPage].
  Future<bool> start({required DateTime endsOn, required int startPage}) {
    final today = _today;
    final end = dateOnly(endsOn).isBefore(today) ? today : endsOn;
    return _commit(
      (book) => KhatmBook(
        active: KhatmPlan(startedOn: today, endsOn: end, startPage: startPage),
        finished: book.finished,
      ),
    );
  }

  /// Move the active plan's last day to [endsOn] (not before today).
  Future<bool> changeEnd(DateTime endsOn) {
    final today = _today;
    final end = dateOnly(endsOn).isBefore(today) ? today : endsOn;
    return _commit((book) =>
        book.active == null ? book : KhatmBook(active: book.active!.copyWith(endsOn: end), finished: book.finished));
  }

  /// Give up the active plan. Finished khatms are kept.
  Future<bool> stop() => _commit((book) => KhatmBook(finished: book.finished));

  /// Counted reading: each page on the day it was read. Pages already read
  /// in this plan keep their first day; reading from before the plan began
  /// is not part of it.
  Future<bool> addPages(ReadingLog pages) => _commit((book) {
        var plan = book.active;
        if (plan == null) return book;
        final days = pages.days.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
        for (final e in days) {
          final day = ReadingLog.parseDay(e.key);
          if (day == null || day.isBefore(plan!.startedOn)) continue;
          plan = plan.reading(day, e.value);
        }
        return _withPlan(book, plan!);
      });

  /// The page map: mark [pages] read today, or unread.
  Future<bool> setRead(Iterable<int> pages, {required bool read}) => _commit((book) {
        final plan = book.active;
        if (plan == null) return book;
        return _withPlan(book, read ? plan.reading(_today, pages) : plan.forgetting(pages));
      });

  /// [book] with [plan] in it; a complete plan moves to finished.
  KhatmBook _withPlan(KhatmBook book, KhatmPlan plan) {
    if (identical(plan, book.active)) return book;
    if (!plan.complete) return KhatmBook(active: plan, finished: book.finished);
    return KhatmBook(finished: [KhatmRecord(startedOn: plan.startedOn, completedOn: _today), ...book.finished]);
  }

  /// Save [change] applied to the book, then show it.
  Future<bool> _commit(KhatmBook Function(KhatmBook) change) {
    final result = _saving.then((_) async {
      final next = change(state);
      if (identical(next, state)) return true;
      if (!await _store.saveKhatm(next)) return false;
      state = next;
      return true;
    });
    _saving = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}
