import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/recognition/models.dart';
import '../../data/quran.dart';
import '../../data/reading_store.dart';

/// Where Taraweeh last got to: the imam's main position (never Al-Fatiha at
/// a rakʿah), kept apart from the personal reading position, which Taraweeh
/// never touches.
///
/// Recorded as the imam moves (saved a few seconds after the last change,
/// so a killed app loses little), and flushed when the mode is left or the
/// app goes to the background. The next night it suggests where to start.
class TaraweehPositionController extends Notifier<SavedPosition?> {
  static const saveDelay = Duration(seconds: 3);

  /// A session this recent is "last night": its end is tonight's likely start.
  static const lastNightWindow = Duration(hours: 36);

  late ReadingStore _store;
  Timer? _timer;
  bool _dirty = false;
  SavedPosition? _latest;

  @override
  SavedPosition? build() {
    _store = ref.read(readingStoreProvider);
    ref.onDispose(() {
      _timer?.cancel();
      final latest = _latest;
      if (_dirty && latest != null) unawaited(_store.saveTaraweehPosition(latest));
    });
    return _latest = _store.taraweehPosition();
  }

  /// The imam is at [position] (confirmed, outside Al-Fatiha).
  void record(Position position) {
    if (state?.verseId == position.verseId) return;
    state = _latest = SavedPosition(verseId: position.verseId, savedAt: DateTime.now());
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(saveDelay, () => unawaited(flush()));
  }

  Future<bool> flush() async {
    _timer?.cancel();
    final latest = _latest;
    if (!_dirty || latest == null) return true;
    final ok = await _store.saveTaraweehPosition(latest);
    if (ok && identical(latest, _latest)) _dirty = false;
    return ok;
  }

  /// Tonight's likely starting point: the juz of the ayah after the one the
  /// last session ended on, if that session was within [lastNightWindow].
  /// A soft hint (a wrong one costs almost nothing, PLAN.md §9), shown and
  /// removable like any other.
  JuzHint? lastNightHint(Quran quran, DateTime now) {
    final last = state;
    if (last == null || now.difference(last.savedAt) > lastNightWindow || now.isBefore(last.savedAt)) return null;
    final next = last.verseId < Quran.verseCount ? last.verseId + 1 : last.verseId;
    return JuzHint(quran.juzOf(next));
  }
}
