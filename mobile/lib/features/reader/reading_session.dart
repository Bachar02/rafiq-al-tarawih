import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/khatm.dart';
import '../../data/reading_store.dart';
import 'page_dwell.dart';

/// The pages waiting for review, and when the app should ask about them.
@immutable
class ReadingSession {
  const ReadingSession({this.pending = const ReadingLog(), this.ask = 0});

  /// Pages that stayed on screen long enough to read, by day, not yet
  /// counted or set aside by the user.
  final ReadingLog pending;

  /// Goes up each time the app should ask the user to review [pending]:
  /// when the app opens on pages from last time, or comes back after a while.
  final int ask;

  ReadingSession copyWith({ReadingLog? pending, int? ask}) =>
      ReadingSession(pending: pending ?? this.pending, ask: ask ?? this.ask);
}

/// What counts as reading, in two steps.
///
/// 1. **Time on the page** ([PageDwell]): a page is proposed once it has been
///    on screen long enough to read it. Scrolling or scrubbing past counts
///    nothing.
/// 2. **The user's review:** proposed pages wait, saved, until the user
///    counts them (all, or the ones he keeps ticked) or sets them aside. The
///    app asks when a session is over: the next time it opens, or when it
///    comes back after [awayBeforeReview]. Counted pages go to the daily log
///    and the khatm plan alike: one definition of reading.
///
/// Waiting pages already show in today's numbers, so progress moves while
/// reading; the review makes them final.
class ReadingSessionController extends Notifier<ReadingSession> {
  static const awayBeforeReview = Duration(minutes: 3);

  late ReadingStore _store;
  late DateTime Function() _now;
  late PageDwell _dwell;
  Timer? _timer;
  int? _page;
  bool _visible = false;
  DateTime? _awaySince;
  bool _dirty = false;

  /// [state], readable during disposal.
  late ReadingSession _latest;

  @override
  ReadingSession build() {
    _store = ref.read(readingStoreProvider);
    _now = ref.read(clockProvider);
    _dwell = PageDwell.forQuran(ref.read(quranProvider));
    ref.onDispose(() {
      _timer?.cancel();
      if (_dirty) unawaited(_store.savePendingReading(_latest.pending));
    });
    final pending = _store.pendingReading();
    // Pages left from last time: ask as the app opens.
    return _latest = ReadingSession(pending: pending, ask: pending.isEmpty ? 0 : 1);
  }

  /// The page at the top of the reader is now [page].
  void showPage(int page) {
    if (page == _page) return;
    _page = page;
    _update();
  }

  /// Whether the reader is in view: the app in the foreground, the Read tab
  /// shown, and no other screen or sheet over it.
  void setVisible(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    _update();
  }

  /// The app went to the background: the session may be over.
  void appPaused() {
    _awaySince ??= _now();
    setVisible(false);
    unawaited(flush());
  }

  /// The app is back. After a while away, the session is over: ask.
  void appResumed() {
    final since = _awaySince;
    _awaySince = null;
    if (since != null && _now().difference(since) >= awayBeforeReview && !_latest.pending.isEmpty) {
      _set(_latest.copyWith(ask: _latest.ask + 1));
    }
  }

  /// The user reviewed [shown] (the pages the sheet listed) and counted
  /// [counted] (some or all of them; none sets them all aside). Counted
  /// pages are saved to the log and the khatm first; then [shown] leaves the
  /// waiting list. False if the counted pages could not be saved: then
  /// nothing changes and they keep waiting.
  Future<bool> review({required ReadingLog shown, required ReadingLog counted}) async {
    if (!counted.isEmpty) {
      if (!await ref.read(readingProgressProvider.notifier).add(counted)) return false;
      if (!await ref.read(khatmProvider.notifier).addPages(counted)) return false;
    }
    _set(_latest.copyWith(pending: _latest.pending.removing(shown)));
    _dirty = true;
    await flush();
    return true;
  }

  /// Save the waiting pages if a change is not saved yet.
  Future<bool> flush() async {
    if (!_dirty) return true;
    final saving = _latest.pending;
    final ok = await _store.savePendingReading(saving);
    if (ok && identical(saving, _latest.pending)) _dirty = false;
    return ok;
  }

  void _update() {
    _timer?.cancel();
    _propose(_dwell.show(_visible ? _page : null, _now()));
    _schedule();
  }

  void _schedule() {
    final left = _dwell.remaining(_now());
    if (left == null) return;
    _timer = Timer(left + const Duration(milliseconds: 50), () {
      _propose(_dwell.tick(_now()));
      _schedule();
    });
  }

  void _propose(List<int> pages) {
    if (pages.isEmpty) return;
    _set(_latest.copyWith(pending: _latest.pending.adding(_now(), pages)));
    _dirty = true;
    unawaited(flush());
  }

  void _set(ReadingSession next) => state = _latest = next;
}

/// Pages read on [day] as the app shows them: counted, and waiting for review.
int pagesReadOn(ReadingLog log, ReadingLog pending, DateTime day) => {...log.on(day), ...pending.on(day)}.length;

/// Pages of [plan] read on [day], counting those waiting for review that the
/// plan does not have yet.
int planPagesReadOn(KhatmPlan plan, ReadingLog pending, DateTime day) =>
    plan.readOn(day) + pending.on(day).where((p) => !plan.pages.containsKey(p)).length;
