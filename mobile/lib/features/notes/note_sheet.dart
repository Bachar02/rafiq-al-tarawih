import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show Bidi;

import '../../app/components/place_tile.dart';
import '../../app/components/sheet.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/note.dart';
import '../../data/quran.dart';
import '../../l10n/l10n.dart';

/// What the note sheet did.
enum NoteSheetResult { saved, deleted }

/// The direction a note is written in: Arabic right to left, French or
/// English left to right, whatever the interface language. Null when the
/// text does not say (empty): the surroundings decide.
TextDirection? noteDirection(String text) {
  if (text.trim().isEmpty) return null;
  return Bidi.detectRtlDirectionality(text) ? TextDirection.rtl : TextDirection.ltr;
}

/// The note sheet for [verse], then what happened, said in a snackbar:
/// saved, or deleted with Undo.
Future<void> editNote(BuildContext context, WidgetRef ref, Verse verse) async {
  final notes = ref.read(notesProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final before = notes.noteFor(verse.id);
  final result = await showNoteSheet(context, verse: verse);
  if (result == NoteSheetResult.saved) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.noteSaved)));
  } else if (result == NoteSheetResult.deleted && before != null) {
    showNoteDeleted(messenger, l, () => notes.restore(before));
  }
}

/// "Note deleted", with Undo.
void showNoteDeleted(ScaffoldMessengerState messenger, AppLocalizations l, VoidCallback undo) => messenger
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(l.noteDeleted), action: SnackBarAction(label: l.undo, onPressed: undo)));

/// Write, edit or delete the note on [verse]. The sheet saves the note
/// itself and closes only once it is kept: a failed save leaves the text in
/// the field and says so. Returns what happened, or null if dismissed.
Future<NoteSheetResult?> showNoteSheet(BuildContext context, {required Verse verse}) =>
    showRubricSheet<NoteSheetResult>(context, builder: (context) => _NoteSheet(verse: verse));

class _NoteSheet extends ConsumerStatefulWidget {
  const _NoteSheet({required this.verse});

  final Verse verse;

  @override
  ConsumerState<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends ConsumerState<_NoteSheet> {
  late final Note? _existing = ref.read(notesProvider.notifier).noteFor(widget.verse.id);
  late final _text = TextEditingController(text: _existing?.text ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() change, NoteSheetResult result, String failure) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await change();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, result);
    } else {
      setState(() {
        _saving = false;
        _error = failure;
      });
    }
  }

  void _save() {
    final l = context.l10n;
    final empty = Note.clean(_text.text).isEmpty;
    _run(
      () => ref.read(notesProvider.notifier).save(widget.verse.id, _text.text),
      empty ? NoteSheetResult.deleted : NoteSheetResult.saved,
      l.noteSaveFailed,
    );
  }

  void _delete() => _run(
        () => ref.read(notesProvider.notifier).delete(widget.verse.id),
        NoteSheetResult.deleted,
        context.l10n.noteDeleteFailed,
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    final names = ref.watch(surahNamesProvider);
    return Padding(
      // Above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(title: l.noteOn(verseReference(widget.verse, names))),
            const SizedBox(height: RubricSpace.s4),
            ValueListenableBuilder(
              valueListenable: _text,
              builder: (context, value, _) => TextField(
                controller: _text,
                autofocus: true,
                minLines: 4,
                maxLines: 10,
                maxLength: Note.maxLength,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                textDirection: noteDirection(value.text),
                decoration: InputDecoration(hintText: l.noteHint, errorText: _error),
              ),
            ),
            const SizedBox(height: RubricSpace.s2),
            ValueListenableBuilder(
              valueListenable: _text,
              builder: (context, value, _) {
                final empty = Note.clean(value.text).isEmpty;
                return FilledButton(
                  // Saving an empty note deletes it; with no note, there is nothing to save.
                  onPressed: _saving || (empty && _existing == null) ? null : _save,
                  child: Text(l.saveNote),
                );
              },
            ),
            if (_existing != null) ...[
              const SizedBox(height: RubricSpace.s2),
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                icon: Icon(Icons.delete_outline, size: 20, color: c.ink),
                label: Text(l.deleteNote),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
