import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/place_tile.dart';
import '../../app/components/surah_tile.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';
import '../../l10n/l10n.dart';

/// Where to read: surahs, juz and pages, each list opened at the current
/// place. The Surahs tab of the home shell, and Taraweeh mode's picker.
class QuranIndex extends ConsumerWidget {
  const QuranIndex({super.key, required this.current, required this.onOpen});

  /// The verse the reader shows now (marked in each list).
  final int current;

  /// A place was chosen: its first verse.
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final l = context.l10n;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: l.tabSurahs), Tab(text: l.tabJuz), Tab(text: l.tabPages)]),
          Expanded(
            child: TabBarView(
              children: [
                _SurahList(quran: quran, names: names, current: current, onOpen: onOpen),
                _JuzList(quran: quran, names: names, current: current, onOpen: onOpen),
                _PageList(quran: quran, names: names, current: current, onOpen: onOpen),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// [QuranIndex] as a screen of its own that pops with the chosen verse id
/// (Taraweeh mode's "Surahs").
class NavigateScreen extends StatelessWidget {
  const NavigateScreen({super.key, required this.current});

  final int current;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.goTo)),
        body: QuranIndex(current: current, onOpen: (verse) => Navigator.of(context).pop(verse)),
      );
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
