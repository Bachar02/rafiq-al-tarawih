import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/place_tile.dart';
import '../../app/navigation.dart';
import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../data/khatm.dart';
import '../../data/reading_store.dart';
import '../khatm/khatm_screen.dart';
import '../../l10n/l10n.dart';

/// Every saved place: the khatm in progress, where the user stopped reading,
/// where Taraweeh ended, then the bookmarks (newest first, or in Quran order). Tap to read there;
/// swipe or the remove button to delete, with Undo. A removal that cannot
/// be saved does not disappear.
class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

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

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l.navBookmarks),
        actions: [
          if (bookmarks.length > 1)
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
      body: ListView(
        padding: const EdgeInsets.only(bottom: RubricSpace.s6),
        children: [
          if (plan != null) ...[
            _Section(l.khatmSection),
            PlaceTile(
              leading: Icon(Icons.flag_outlined, color: c.inkSecondary),
              title: l.khatmCard(plan.read),
              subtitle: '${l.todayProgress(plan.readOn(now), plan.todayTarget(dateOnly(now)))} · '
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
            Padding(
              padding: const EdgeInsets.fromLTRB(RubricSpace.s6, RubricSpace.s2, RubricSpace.s6, 0),
              child: Text(l.noBookmarksHint, style: RubricText.label.copyWith(color: c.inkSecondary)),
            )
          else
            for (final b in bookmarks)
              Dismissible(
                key: ValueKey(b.verseId),
                direction: DismissDirection.endToStart,
                // Gone from the list only once the removal is saved.
                confirmDismiss: (_) => remove(b),
                background: Container(
                  color: c.surfaceRaised,
                  alignment: AlignmentDirectional.centerEnd,
                  padding: const EdgeInsetsDirectional.only(end: RubricSpace.s6),
                  child: Icon(Icons.bookmark_remove_outlined, color: c.ink),
                ),
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
      ),
    );
  }
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
