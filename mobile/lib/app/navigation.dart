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

/// The Bookmarks tab's two views. Kept here, not in the tab, so the tab
/// opens on the view the user left, and "Back to notes" finds the notes.
enum BookmarksView { bookmarks, notes }

class BookmarksViewController extends Notifier<BookmarksView> {
  @override
  BookmarksView build() => BookmarksView.bookmarks;

  void select(BookmarksView view) => state = view;
}

final bookmarksViewProvider = NotifierProvider<BookmarksViewController, BookmarksView>(BookmarksViewController.new);

/// Where the reader was sent from, so the user can go back there.
sealed class ReaderOrigin {
  const ReaderOrigin();
}

/// A tab (Surahs, Bookmarks), and for Bookmarks which view.
final class TabOrigin extends ReaderOrigin {
  const TabOrigin(this.tab, {this.view});

  final HomeTab tab;
  final BookmarksView? view;

  @override
  bool operator ==(Object other) => other is TabOrigin && other.tab == tab && other.view == view;

  @override
  int get hashCode => Object.hash(tab, view);
}

/// The khatm planner, opened from [tab].
final class KhatmOrigin extends ReaderOrigin {
  const KhatmOrigin(this.tab);

  final HomeTab tab;

  @override
  bool operator ==(Object other) => other is KhatmOrigin && other.tab == tab;

  @override
  int get hashCode => tab.hashCode;
}

/// A search, with what was typed.
final class SearchOrigin extends ReaderOrigin {
  const SearchOrigin(this.query);

  final String query;

  @override
  bool operator ==(Object other) => other is SearchOrigin && other.query == query;

  @override
  int get hashCode => query.hashCode;
}

/// "Show this ayah in the reader", from another tab. [serial] makes two
/// requests for the same ayah two events.
@immutable
class ReaderRequest {
  const ReaderRequest({required this.verseId, required this.mark, required this.serial, this.from});

  final int verseId;

  /// Mark the ayah for a moment, so the eye finds it.
  final bool mark;
  final int serial;

  /// Where the user can go back to.
  final ReaderOrigin? from;
}

class ReaderRequests extends Notifier<ReaderRequest?> {
  @override
  ReaderRequest? build() => null;

  /// Switch to the reader and open it at [verseId]; [from] is offered as the
  /// way back.
  void open(int verseId, {bool mark = false, ReaderOrigin? from}) {
    state = ReaderRequest(verseId: verseId, mark: mark, serial: (state?.serial ?? 0) + 1, from: from);
    ref.read(homeTabProvider.notifier).select(HomeTab.read);
  }
}

final readerRequestsProvider = NotifierProvider<ReaderRequests, ReaderRequest?>(ReaderRequests.new);

/// The way back from a jump into the reader: where it came from, and the
/// reading place before the jump.
@immutable
class ReaderReturn {
  const ReaderReturn({required this.to, required this.previousVerse, required this.landedPage});

  final ReaderOrigin to;

  /// The reading position before the jump.
  final int previousVerse;

  /// The page the jump landed on. Going back while still on it was only a
  /// look: the reading position goes back to [previousVerse].
  final int landedPage;
}

/// The reader's way back, while there is one. Set by a jump from elsewhere;
/// cleared when the user goes back, or moves to another tab.
class ReaderReturnController extends Notifier<ReaderReturn?> {
  @override
  ReaderReturn? build() => null;

  void set(ReaderReturn value) => state = value;

  void clear() => state = null;
}

final readerReturnProvider = NotifierProvider<ReaderReturnController, ReaderReturn?>(ReaderReturnController.new);
