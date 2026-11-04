import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/reading_store.dart';

/// The user's bookmarks, newest first, one per ayah.
///
/// Every change is saved before it is shown: if the save fails, the list on
/// screen stays as it was and the caller says so, so the app never shows a
/// bookmark it has not kept (or hides one it still has).
class BookmarksController extends Notifier<List<Bookmark>> {
  @override
  List<Bookmark> build() => ref.read(readingStoreProvider).bookmarks();

  bool contains(int verseId) => state.any((b) => b.verseId == verseId);

  Future<bool> add(int verseId) =>
      _commit([Bookmark(verseId: verseId, createdAt: DateTime.now()), ...state.where((b) => b.verseId != verseId)]);

  Future<bool> remove(int verseId) => _commit([...state.where((b) => b.verseId != verseId)]);

  Future<bool> _commit(List<Bookmark> next) async {
    final ok = await ref.read(readingStoreProvider).saveBookmarks(next);
    if (ok) state = List.unmodifiable(next);
    return ok;
  }
}
