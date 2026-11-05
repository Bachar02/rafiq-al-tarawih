import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/reading_store.dart';

/// The pages read each day, as the user confirmed them: the daily goal's
/// count, and later the reading-discipline chart.
///
/// Pages arrive only through the review of a reading session
/// ([ReadingSessionController]): the reader proposes the pages that stayed
/// on screen long enough to read, and the user counts them. Saved before
/// they are shown.
class ReadingProgressController extends Notifier<ReadingLog> {
  @override
  ReadingLog build() => ref.read(readingStoreProvider).readingLog();

  /// Add [pages] (by the day they were read).
  Future<bool> add(ReadingLog pages) async {
    if (pages.isEmpty) return true;
    final next = state.merging(pages);
    if (!await ref.read(readingStoreProvider).saveReadingLog(next)) return false;
    state = next;
    return true;
  }
}
