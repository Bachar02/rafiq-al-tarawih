import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/recognition/models.dart';
import '../../data/quran.dart';
import '../../data/reading_store.dart';
import '../../data/taraweeh_ledger.dart';

/// Taraweeh night by night: what the imam was heard reciting, and where it
/// stopped ([TaraweehLedger], PLAN.md §39). Kept apart from the personal
/// reading position, which Taraweeh never touches.
///
/// Fed by the listening session with committed results only, never asked
/// anything during prayer. Saved a few seconds after each change (a killed
/// app loses little), and at once when the mode is left, the app goes to the
/// background, or the user corrects a night. Before the first save, the
/// single position of earlier versions is carried over.
class TaraweehProgressController extends Notifier<TaraweehLedger> {
  static const saveDelay = Duration(seconds: 3);

  /// A night this recent is "last night": its end is tonight's likely start.
  static const lastNightWindow = Duration(hours: 36);

  late ReadingStore _store;
  Timer? _timer;
  bool _dirty = false;

  /// [state], readable while disposing (Riverpod forbids reading it there).
  TaraweehLedger _latest = TaraweehLedger.empty;

  @override
  TaraweehLedger build() {
    _store = ref.read(readingStoreProvider);
    ref.onDispose(() {
      _timer?.cancel();
      if (_dirty) unawaited(_store.saveTaraweehLedger(_latest));
    });
    final saved = _store.taraweehLedger();
    final legacy = saved == null ? _store.taraweehPosition() : null;
    return _latest =
        saved ?? (legacy == null ? TaraweehLedger.empty : TaraweehLedger.fromLegacy(legacy.verseId, legacy.savedAt));
  }

  /// The imam was heard reciting [position], committed: a final result the
  /// engine is sure of, or "the imam is here". Previews never come here.
  void observe(Position position, DateTime at) => _change(state.observe(position.verseId, at), soon: false);

  /// "Taraweeh ended at [verseId]", afterwards. Returns the ledger before,
  /// for Undo ([restore]).
  TaraweehLedger correct(int verseId, DateTime at) {
    final before = state;
    _change(state.correct(verseId, at), soon: true);
    return before;
  }

  /// Undo of [correct].
  void restore(TaraweehLedger ledger) => _change(ledger, soon: true);

  void _change(TaraweehLedger next, {required bool soon}) {
    if (identical(next, _latest)) return;
    state = _latest = next;
    _dirty = true;
    _timer?.cancel();
    if (soon) {
      unawaited(flush());
    } else {
      _timer = Timer(saveDelay, () => unawaited(flush()));
    }
  }

  Future<bool> flush() async {
    _timer?.cancel();
    if (!_dirty) return true;
    final saving = _latest;
    final ok = await _store.saveTaraweehLedger(saving);
    if (ok && identical(saving, _latest)) _dirty = false;
    return ok;
  }

  /// Tonight's likely starting point: the juz of the ayah after where
  /// Taraweeh stopped, if that was within [lastNightWindow] (after a night
  /// or more without Taraweeh, the imam has moved on by an unknown amount).
  /// A soft hint (a wrong one costs almost nothing, PLAN.md §9), shown and
  /// removable like any other.
  JuzHint? lastNightHint(Quran quran, DateTime now) {
    final last = state.progress(quran);
    if (last == null || now.difference(last.at) > lastNightWindow || now.isBefore(last.at)) return null;
    final next = last.verseId < Quran.verseCount ? last.verseId + 1 : last.verseId;
    return JuzHint(quran.juzOf(next));
  }
}
