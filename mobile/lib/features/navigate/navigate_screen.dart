import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/place_tile.dart';
import '../../app/components/surah_tile.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/quran.dart';
import '../../data/reading_store.dart';
import '../../data/surah_names.dart';
import '../../l10n/l10n.dart';

/// Where to read: surahs, juz, pages and bookmarks, each list opened at the
/// current place. Pops with the chosen verse id.
class NavigateScreen extends ConsumerWidget {
  const NavigateScreen({super.key, required this.current, this.initialTab = 0});

  /// The verse the reader shows now (marked in each list).
  final int current;
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    void open(int verseId) => Navigator.of(context).pop(verseId);
    final l = context.l10n;

    return DefaultTabController(
      length: 4,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.goTo),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: l.tabSurahs), Tab(text: l.tabJuz), Tab(text: l.tabPages), Tab(text: l.tabBookmarks)],
          ),
        ),
        body: TabBarView(
          children: [
            _SurahList(quran: quran, names: names, current: current, onOpen: open),
            _JuzList(quran: quran, names: names, current: current, onOpen: open),
            _PageList(quran: quran, names: names, current: current, onOpen: open),
            _Bookmarks(quran: quran, names: names, onOpen: open),
          ],
        ),
      ),
    );
  }
}

/// The surah list, filtered by name or number, opened at the current surah.
class _SurahList extends StatefulWidget {
  const _SurahList({required this.quran, required this.names, required this.current, required this.onOpen});

  final Quran quran;
  final SurahNames names;
  final int current;
  final ValueChanged<int> onOpen;

  @override
  State<_SurahList> createState() => _SurahListState();
}

class _SurahListState extends State<_SurahList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final surahs = searchSurahs(widget.quran, widget.names, _query);
    final current = widget.quran.verse(widget.current).surah;
    Widget row(int i) => SurahTile(
          surah: surahs[i],
          names: widget.names,
          selected: surahs[i].index == current,
          onTap: () => widget.onOpen(surahs[i].firstVerseId),
        );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(RubricSpace.s4, RubricSpace.s3, RubricSpace.s4, RubricSpace.s2),
          child: TextField(
            decoration:
                InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.l10n.searchByNameOrNumber),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: surahs.isEmpty
              ? const SizedBox.shrink()
              : _UniformList(
                  count: surahs.length,
                  openAt: _query.isEmpty ? current - 1 : 0,
                  padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s2),
                  row: row,
                ),
        ),
      ],
    );
  }
}

class _JuzList extends StatelessWidget {
  const _JuzList({required this.quran, required this.names, required this.current, required this.onOpen});

  final Quran quran;
  final SurahNames names;
  final int current;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final here = quran.juzOf(current);
    return _UniformList(
      count: quran.juzs.count,
      openAt: here - 1,
      row: (i) {
        final start = quran.verse(quran.juzs.start(i + 1));
        return PlaceTile(
          selected: i + 1 == here,
          title: context.l10n.juzNumber(i + 1),
          subtitle: context.l10n.fromPlacePage(verseReference(start, names), quran.pageOf(start.id)),
          onTap: () => onOpen(start.id),
        );
      },
    );
  }
}

/// All 604 pages; each opens where it begins.
class _PageList extends StatelessWidget {
  const _PageList({required this.quran, required this.names, required this.current, required this.onOpen});

  final Quran quran;
  final SurahNames names;
  final int current;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final here = quran.pageOf(current);
    final percent = (here * 100 / quran.pages.count).floor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(RubricSpace.s4, RubricSpace.s3, RubricSpace.s4, RubricSpace.s1),
          child: Text(
            context.l10n.khatmProgress(here, quran.pages.count, percent),
            style: RubricText.caption.copyWith(color: context.colors.inkSecondary),
          ),
        ),
        Expanded(
            child: _UniformList(
          count: quran.pages.count,
          openAt: here - 1,
          row: (i) {
            final start = quran.verse(quran.pages.start(i + 1));
            return PlaceTile(
              selected: i + 1 == here,
              title: context.l10n.pageNumber(i + 1),
              subtitle: context.l10n.fromPlaceJuz(verseReference(start, names), quran.juzOf(start.id)),
              onTap: () => onOpen(start.id),
            );
          },
        )),
      ],
    );
  }
}

/// A list of same-shaped rows, opened with row [openAt] near the top.
///
/// The first row is the prototype: it is measured once and sizes them all,
/// so 604 pages scroll without measuring each, and the opening offset is
/// exact at any text size (total extent ÷ rows, after the first layout).
class _UniformList extends StatefulWidget {
  const _UniformList({required this.count, required this.openAt, required this.row, this.padding});

  final int count;
  final int openAt;
  final Widget Function(int index) row;
  final EdgeInsets? padding;

  @override
  State<_UniformList> createState() => _UniformListState();
}

class _UniformListState extends State<_UniformList> {
  final _controller = ScrollController();

  /// Rows shown above the current one, for context.
  static const _above = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void didUpdateWidget(_UniformList old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count && _controller.hasClients) _controller.jumpTo(0);
  }

  void _open() {
    if (!mounted || !_controller.hasClients) return;
    final p = _controller.position;
    final extent = (p.maxScrollExtent + p.viewportDimension - (widget.padding?.vertical ?? 0)) / widget.count;
    final target = (widget.openAt - _above) * extent;
    _controller.jumpTo(target.clamp(0, p.maxScrollExtent));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
        controller: _controller,
        padding: widget.padding,
        prototypeItem: widget.row(0),
        itemCount: widget.count,
        itemBuilder: (context, i) => widget.row(i),
      );
}

/// Where Taraweeh last ended, then the bookmarks, newest first. Removing one
/// can be undone.
class _Bookmarks extends ConsumerWidget {
  const _Bookmarks({required this.quran, required this.names, required this.onOpen});

  final Quran quran;
  final SurahNames names;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l = context.l10n;
    final bookmarks = ref.watch(bookmarksProvider);
    final taraweeh = ref.watch(taraweehPositionProvider);

    Future<void> remove(Bookmark bookmark) async {
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
    }

    return ListView(
      children: [
        if (taraweeh != null)
          PlaceTile(
            leading: Icon(Icons.mic_none, color: c.inkSecondary),
            title: l.whereTaraweehEnded,
            subtitle: '${verseReference(quran.verse(taraweeh.verseId), names)} · ${_when(l, taraweeh.savedAt)}',
            onTap: () => onOpen(taraweeh.verseId),
          ),
        if (bookmarks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(RubricSpace.s6),
            child: Text(
              l.noBookmarks,
              textAlign: TextAlign.center,
              style: RubricText.label.copyWith(color: c.inkSecondary),
            ),
          )
        else
          for (final b in bookmarks)
            PlaceTile(
              title: verseReference(quran.verse(b.verseId), names),
              subtitle: verseLocation(l, quran, b.verseId),
              verse: quran.verse(b.verseId),
              onTap: () => onOpen(b.verseId),
              trailing: IconButton(
                tooltip: l.removeBookmark,
                icon: const Icon(Icons.bookmark_remove_outlined),
                onPressed: () => remove(b),
              ),
            ),
      ],
    );
  }

  static String _when(AppLocalizations l, DateTime at) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(at.year, at.month, at.day)).inDays;
    return switch (days) {
      <= 0 => l.today,
      1 => l.yesterday,
      _ => l.daysAgo(days),
    };
  }
}
