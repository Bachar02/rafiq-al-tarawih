import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/quran.dart';
import '../../data/reading_store.dart';

/// Pages read each day, for the daily reading goal.
///
/// **A page counts when the reader moves forward past it**, by scrolling or
/// turning one or two pages at a time: reading is moving through the text.
/// A jump (Go to, search, a bookmark) counts nothing, so the number cannot be
/// inflated by navigating, and the page a session ends on counts once the
/// reader moves on from it. The last page of the Quran counts when reached.
///
/// Saved a moment after each change and flushed when the app goes to the
/// background, like the reading position.
class ReadingProgressController extends Notifier<ReadingLog> {
  static const saveDelay = Duration(seconds: 2);

  /// Moves of more than this many pages are jumps, not reading.
  static const maxStep = 2;

  late ReadingStore _store;
  late DateTime Function() _now;
  Timer? _timer;
  bool _dirty = false;
  late ReadingLog _latest;
  int? _lastPage;

  @override
  ReadingLog build() {
    _store = ref.read(readingStoreProvider);
    _now = ref.read(clockProvider);
    ref.onDispose(() {
      _timer?.cancel();
      if (_dirty) unawaited(_store.saveReadingLog(_latest));
    });
    return _latest = _store.readingLog();
  }

  /// Pages read today.
  int get today => state.on(_now()).length;

  /// The reader landed on [page] by a jump (or opened there): nothing read.
  void jumpedTo(int page) => _lastPage = page;

  /// The reader moved to [page] by scrolling or turning.
  void movedTo(int page) {
    final last = _lastPage;
    _lastPage = page;
    if (last == null) return;
    final step = page - last;
    if (step < 1 || step > maxStep) return;
    final read = [for (var p = last; p < page; p++) p, if (page == Quran.pageCount) page];
    _latest = _latest.adding(_now(), read);
    state = _latest;
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(saveDelay, () => unawaited(flush()));
  }

  Future<bool> flush() async {
    _timer?.cancel();
    if (!_dirty) return true;
    final saving = _latest;
    final ok = await _store.saveReadingLog(saving);
    if (ok && identical(saving, _latest)) _dirty = false;
    return ok;
  }
}
