import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/khatm.dart';
import '../../data/reading_store.dart';

/// The khatm plan: one active plan at most, and the finished ones.
///
/// Starting, changing the end and stopping are saved before they are shown,
/// so the screen never claims a plan the app has not kept. Pages read are
/// recorded as the reader moves on ([ReadingProgressController] decides
/// what reading is) and saved a moment later, and when the app goes to the
/// background, like the reading log. A failed save stays pending.
class KhatmController extends Notifier<KhatmBook> {
  static const saveDelay = Duration(seconds: 2);

  late ReadingStore _store;
  late DateTime Function() _now;
  Timer? _timer;
  bool _dirty = false;

  /// [state], readable during disposal.
  late KhatmBook _latest;

  /// Saves run one after another, so an older book never lands last.
  Future<void> _saving = Future.value();

  @override
  KhatmBook build() {
    _store = ref.read(readingStoreProvider);
    _now = ref.read(clockProvider);
    ref.onDispose(() {
      _timer?.cancel();
      if (_dirty) unawaited(_store.saveKhatm(_latest));
    });
    return _latest = _store.khatm();
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

  /// The reader read on past [pages] today. Pages already read in this plan
  /// add nothing. The last page completes the khatm.
  void recordPages(Iterable<int> pages) {
    final plan = _latest.active;
    if (plan == null) return;
    final today = _today;
    final next = plan.reading(today, pages);
    if (identical(next, plan)) return;
    _latest = next.complete
        ? KhatmBook(
            finished: [KhatmRecord(startedOn: plan.startedOn, completedOn: today), ..._latest.finished],
          )
        : KhatmBook(active: next, finished: _latest.finished);
    state = _latest;
    _dirty = true;
    _timer?.cancel();
    // A completed khatm is saved at once; reading in progress a moment later.
    _timer = Timer(next.complete ? Duration.zero : saveDelay, () => unawaited(flush()));
  }

  /// Save now if anything is pending (the app is going to the background).
  Future<bool> flush() {
    _timer?.cancel();
    return _serially(() async {
      if (!_dirty) return true;
      final saving = _latest;
      final ok = await _store.saveKhatm(saving);
      if (ok && identical(saving, _latest)) _dirty = false;
      return ok;
    });
  }

  /// Save [change] applied to the book, then show it.
  Future<bool> _commit(KhatmBook Function(KhatmBook) change) {
    _timer?.cancel();
    return _serially(() async {
      final base = _latest;
      final next = change(base);
      if (!await _store.saveKhatm(next)) return false;
      if (identical(_latest, base)) {
        _latest = next;
        _dirty = false;
      } else {
        // Pages were read while saving: keep them, on top of the change.
        _latest = change(_latest);
        _dirty = true;
        _timer = Timer(saveDelay, () => unawaited(flush()));
      }
      state = _latest;
      return true;
    });
  }

  Future<bool> _serially(Future<bool> Function() save) {
    final result = _saving.then((_) => save());
    _saving = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}
