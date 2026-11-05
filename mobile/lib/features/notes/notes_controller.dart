import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/note.dart';

/// The user's notes, newest edit first, one per ayah.
///
/// Every change is saved before it is shown: if the save fails, the list
/// stays as it was and the caller says so (the note sheet stays open, with
/// the text still in it).
class NotesController extends Notifier<List<Note>> {
  @override
  List<Note> build() => ref.read(readingStoreProvider).notes();

  Note? noteFor(int verseId) => state.where((n) => n.verseId == verseId).firstOrNull;

  /// Save [text] as the note on [verseId]. An empty text deletes the note.
  Future<bool> save(int verseId, String text) {
    final clean = Note.clean(text);
    if (clean.isEmpty) return delete(verseId);
    final existing = noteFor(verseId);
    if (existing != null && existing.text == clean) return Future.value(true);
    final now = ref.read(clockProvider)();
    final note = Note(verseId: verseId, text: clean, createdAt: existing?.createdAt ?? now, updatedAt: now);
    return _commit([note, ...state.where((n) => n.verseId != verseId)]);
  }

  Future<bool> delete(int verseId) =>
      noteFor(verseId) == null ? Future.value(true) : _commit([...state.where((n) => n.verseId != verseId)]);

  /// Put back a deleted note as it was (Undo), with its dates and place.
  Future<bool> restore(Note note) => _commit(
        [...state.where((n) => n.verseId != note.verseId), note]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      );

  Future<bool> _commit(List<Note> next) async {
    final ok = await ref.read(readingStoreProvider).saveNotes(next);
    if (ok) state = List.unmodifiable(next);
    return ok;
  }
}
