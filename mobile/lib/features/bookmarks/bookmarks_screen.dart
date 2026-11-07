import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/place_tile.dart';
import '../../app/components/quran_text.dart' show noteIcon;
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../data/khatm.dart';
import '../../data/note.dart';
import '../../data/reading_store.dart';
import '../../l10n/l10n.dart';
import '../khatm/khatm_screen.dart';
import '../notes/note_sheet.dart';
import '../progress/progress_screen.dart';
import '../reader/reading_session.dart';

/// Every saved place, in two views.
///
/// **Bookmarks:** the reading chart, the khatm in progress, where the user stopped reading,
/// where Taraweeh ended, then the bookmarks (newest first, or in Quran
/// order). **Notes:** the user's notes, newest edit first.
///
/// Tap to read there; swipe (or the remove button) to delete, with Undo. A
/// removal that cannot be saved does not disappear.
class BookmarksScreen extends ConsumerStatefulWidget {
  const BookmarksScreen({super.key});

  @override
  ConsumerState<BookmarksScreen> createState() => _BookmarksScreenState();
}

enum _View { bookmarks, notes }

class _BookmarksScreenState extends ConsumerState<BookmarksScreen> {
  _View _view = _View.bookmarks;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final quranOrder = ref.watch(settingsProvider.select((s) => s.bookmarksInQuranOrder));
    final bookmarks = ref.watch(bookmarksProvider.select((b) => b.length));
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l.navBookmarks),
        actions: [
          if (_view == _View.bookmarks && bookmarks > 1)
            PopupMenuButton<bool>(
              tooltip: l.sortBookmarks,
              icon: const Icon(Icons.sort),
              onSelected: (inOrder) =>
                  ref.read(settingsProvider.notifier).update((s) => s.copyWith(bookmarksInQuranOrder: inOrder)),
              itemBuilder: (context) => [
                CheckedPopupMenuItem(value: false, checked: !quranOrder, child: Text(l.sortNewest)),
                CheckedPopupMenuItem(value: true, checked: quranOrder, child: Text(l.sortQuranOrder)),
              ],
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // In the body, not the app bar: it grows with large system text.
          Padding(
            padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s1, RubricSpace.gutter, 0),
            child: SegmentedButton<_View>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _View.bookmarks,
                  icon: const Icon(Icons.bookmark_outline, size: 18),
                  label: Text(l.navBookmarks),
                ),
                ButtonSegment(value: _View.notes, icon: const Icon(noteIcon, size: 18), label: Text(l.notes)),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          Expanded(
            child: switch (_view) {
              _View.bookmarks => const _BookmarksList(),
              _View.notes => const _NotesList(),
            },
          ),
        ],
      ),
    );
  }
}

class _BookmarksList extends ConsumerWidget {
  const _BookmarksList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final reading = ref.watch(readingPositionProvider);
    final taraweeh = ref.watch(taraweehPositionProvider);
    final quranOrder = ref.watch(settingsProvider.select((s) => s.bookmarksInQuranOrder));
    final bookmarks = [...ref.watch(bookmarksProvider)];
    if (quranOrder) bookmarks.sort((a, b) => a.verseId.compareTo(b.verseId));
    final now = ref.read(clockProvider)();
    final plan = ref.watch(khatmProvider.select((b) => b.active));
    final pending = ref.watch(readingSessionProvider.select((s) => s.pending));

    void open(int verseId, {bool mark = true}) => ref.read(readerRequestsProvider.notifier).open(verseId, mark: mark);

    Future<bool> remove(Bookmark bookmark) async {
      final controller = ref.read(bookmarksProvider.notifier);
      final messenger = ScaffoldMessenger.of(context);
      final ok = await controller.remove(bookmark.verseId);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          ok
              ? SnackBar(
                  content: Text(l.bookmarkRemoved),
                  action: SnackBarAction(label: l.undo, onPressed: () => controller.restore(bookmark)),
                )
              : SnackBar(content: Text(l.bookmarkRemoveFailed)),
        );
      return ok;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: RubricSpace.s6),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s3, RubricSpace.gutter, 0),
          child: ReadingCard(),
        ),
        if (plan != null) ...[
          _Section(l.khatmSection),
          PlaceTile(
            leading: Icon(Icons.flag_outlined, color: c.inkSecondary),
            title: l.khatmCard(plan.read),
            subtitle: '${l.todayProgress(planPagesReadOn(plan, pending, now), plan.todayTarget(dateOnly(now)))} · '
                '${khatmTimeLine(l, plan, dateOnly(now))}',
            trailing: Icon(Icons.chevron_right, color: c.inkSecondary),
            onTap: () => AppRoutes.khatm(context),
          ),
        ],
        _Section(l.continueReading),
        PlaceTile(
          leading: Icon(Icons.menu_book_outlined, color: c.inkSecondary),
          title: verseReference(quran.verse(reading), names),
          subtitle: verseLocation(l, quran, reading),
          onTap: () => open(reading, mark: false),
        ),
        if (taraweeh != null)
          PlaceTile(
            leading: Icon(Icons.mic_none, color: c.inkSecondary),
            title: l.whereTaraweehEnded,
            subtitle:
                '${verseReference(quran.verse(taraweeh.verseId), names)} · ${relativeDay(l, taraweeh.savedAt, now)}',
            onTap: () => open(taraweeh.verseId),
          ),
        _Section(l.bookmarksCount(bookmarks.length)),
        if (bookmarks.isEmpty)
          _Empty(l.noBookmarksHint)
        else
          for (final b in bookmarks)
            Dismissible(
              key: ValueKey(b.verseId),
              direction: DismissDirection.endToStart,
              // Gone from the list only once the removal is saved.
              confirmDismiss: (_) => remove(b),
              background: _SwipeBackground(Icons.bookmark_remove_outlined),
              child: PlaceTile(
                title: verseReference(quran.verse(b.verseId), names),
                subtitle: '${verseLocation(l, quran, b.verseId)} · ${relativeDay(l, b.createdAt, now)}',
                verse: quran.verse(b.verseId),
                onTap: () => open(b.verseId),
                trailing: IconButton(
                  tooltip: l.removeBookmark,
                  icon: const Icon(Icons.bookmark_remove_outlined),
                  onPressed: () => remove(b),
                ),
              ),
            ),
      ],
    );
  }
}

class _NotesList extends ConsumerWidget {
  const _NotesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = context.colors;
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final notes = ref.watch(notesProvider);
    final now = ref.read(clockProvider)();

    Future<bool> delete(Note note) async {
      final controller = ref.read(notesProvider.notifier);
      final messenger = ScaffoldMessenger.of(context);
      final ok = await controller.delete(note.verseId);
      if (ok) {
        showNoteDeleted(messenger, l, () => controller.restore(note));
      } else {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l.noteDeleteFailed)));
      }
      return ok;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: RubricSpace.s6),
      children: [
        _Section(l.notesCount(notes.length)),
        if (notes.isEmpty)
          _Empty(l.noNotesHint)
        else
          for (final n in notes)
            Dismissible(
              key: ValueKey(n.verseId),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) => delete(n),
              background: _SwipeBackground(Icons.delete_outline),
              child: ListTile(
                onTap: () => ref.read(readerRequestsProvider.notifier).open(n.verseId, mark: true),
                contentPadding: const EdgeInsetsDirectional.only(start: RubricSpace.s4, end: RubricSpace.s2),
                title:
                    Text(verseReference(quran.verse(n.verseId), names), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${verseLocation(l, quran, n.verseId)} · ${relativeDay(l, n.updatedAt, now)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: RubricSpace.s1),
                      child: Text(
                        n.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        // In the direction it is written, aligned to its own start.
                        textDirection: noteDirection(n.text),
                        textAlign: TextAlign.start,
                        style: RubricText.label.copyWith(color: c.ink),
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  tooltip: l.editNote,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => editNote(context, ref, quran.verse(n.verseId)),
                ),
              ),
            ),
      ],
    );
  }
}

/// What a list holds when it is empty, and how to fill it.
class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(RubricSpace.s6, RubricSpace.s2, RubricSpace.s6, 0),
        child: Text(text, style: RubricText.label.copyWith(color: context.colors.inkSecondary)),
      );
}

/// Behind a row being swiped away.
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        color: context.colors.surfaceRaised,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: RubricSpace.s6),
        child: Icon(icon, color: context.colors.ink),
      );
}

/// A section's overline.
class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(RubricSpace.s4, RubricSpace.s6, RubricSpace.s4, RubricSpace.s1),
        child: Text(
          text.toUpperCase(),
          style: RubricText.overlineFor(context).copyWith(color: context.colors.inkSecondary),
        ),
      );
}
