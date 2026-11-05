/// The home shell's state: which tab is shown, and places other tabs ask the
/// reader to open. Kept apart from the widgets so any screen can ask, and
/// tests can check, without reaching into widget state.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shell's tabs. Taraweeh is not a tab: its button opens the full-screen
/// mode and starts listening (one tap, PLAN.md §18).
enum HomeTab { read, surahs, bookmarks, more }

class HomeTabController extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.read;

  void select(HomeTab tab) => state = tab;
}

final homeTabProvider = NotifierProvider<HomeTabController, HomeTab>(HomeTabController.new);

/// "Show this ayah in the reader", from another tab. [serial] makes two
/// requests for the same ayah two events.
@immutable
class ReaderRequest {
  const ReaderRequest({required this.verseId, required this.mark, required this.serial});

  final int verseId;

  /// Mark the ayah for a moment, so the eye finds it.
  final bool mark;
  final int serial;
}

class ReaderRequests extends Notifier<ReaderRequest?> {
  @override
  ReaderRequest? build() => null;

  /// Switch to the reader and open it at [verseId].
  void open(int verseId, {bool mark = false}) {
    state = ReaderRequest(verseId: verseId, mark: mark, serial: (state?.serial ?? 0) + 1);
    ref.read(homeTabProvider.notifier).select(HomeTab.read);
  }
}

final readerRequestsProvider = NotifierProvider<ReaderRequests, ReaderRequest?>(ReaderRequests.new);
