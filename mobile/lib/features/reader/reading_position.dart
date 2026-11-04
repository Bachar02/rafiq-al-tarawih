import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/reading_store.dart';

/// The personal reading position: the verse at the top of the reader.
///
/// Updated on every scroll that changes the top verse, saved a moment after
/// scrolling stops (not on every frame), and flushed when the app goes to
/// the background. A failed save stays pending and is retried with the next
/// change or flush. Taraweeh mode never touches it.
class ReadingPositionController extends Notifier<int> {
  static const saveDelay = Duration(seconds: 1);

  late ReadingStore _store;
  Timer? _timer;
  bool _dirty = false;

  /// [state], readable during disposal (when `state` is not).
  int _latest = 1;

  @override
  int build() {
    _store = ref.read(readingStoreProvider);
    ref.onDispose(() {
      _timer?.cancel();
      if (_dirty) unawaited(_store.saveReadingPosition(SavedPosition(verseId: _latest, savedAt: DateTime.now())));
    });
    return _latest = _store.readingPosition()?.verseId ?? 1;
  }

  /// The reader now shows [verseId] at the top.
  void update(int verseId) {
    if (verseId == state && !_dirty) return;
    state = _latest = verseId;
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(saveDelay, () => unawaited(_save()));
  }

  /// Save now if anything is pending (the app is going to the background).
  Future<bool> flush() async {
    _timer?.cancel();
    if (!_dirty) return true;
    return _save();
  }

  Future<bool> _save() async {
    final verse = state;
    final ok = await _store.saveReadingPosition(SavedPosition(verseId: verse, savedAt: DateTime.now()));
    if (ok && verse == state) _dirty = false;
    return ok;
  }
}
