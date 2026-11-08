import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/place_tile.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';
import 'quran_search.dart';
import '../../l10n/l10n.dart';

/// Search the Quran: one field for references, pages, juz, surah names and
/// Arabic text. Pops with the chosen verse and what was typed, so the reader
/// can bring the user back to these results.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.query = ''});

  /// Already typed when the screen opens (back from a result).
  final String query;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

/// A result the user chose, and the search that found it.
typedef SearchChoice = ({int verseId, String query});

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _field = TextEditingController();
  String _query = '';
  SearchResults _results = SearchResults.empty;

  @override
  void initState() {
    super.initState();
    if (widget.query.isEmpty) return;
    _field.text = widget.query;
    _query = widget.query;
    _results = ref.read(quranSearchProvider).search(widget.query);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _search(String query) {
    if (query == _query) return;
    // A scan of 6,236 short strings: milliseconds, so no debounce or isolate.
    setState(() {
      _query = query;
      _results = ref.read(quranSearchProvider).search(query);
    });
  }

  void _open(int verseId) => Navigator.of(context).pop<SearchChoice>((verseId: verseId, query: _query));

  @override
  Widget build(BuildContext context) {
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final c = context.colors;
    final l = context.l10n;
    final r = _results;

    final rows = <Widget>[
      if (r.textTooShort) _Message(l.searchTooShort(QuranSearch.minLetters)),
      for (final t in r.targets) _target(l, t, quran, names),
      if (r.ayahs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(RubricSpace.s4, RubricSpace.s4, RubricSpace.s4, RubricSpace.s1),
          child: Text(
            // Overlines are Latin capitals (brand book §4); Arabic has no case.
            (r.ayahTotal > r.ayahs.length ? l.searchFirstOf(r.ayahs.length, r.ayahTotal) : l.ayahCount(r.ayahTotal))
                .toUpperCase(),
            style: RubricText.overlineFor(context).copyWith(color: c.inkSecondary),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsetsDirectional.only(end: RubricSpace.s4),
          child: TextField(
            controller: _field,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l.searchHint,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l.clear,
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _field.clear();
                        _search('');
                      },
                    ),
            ),
            onChanged: _search,
          ),
        ),
      ),
      body: _query.trim().isEmpty
          ? const _Help()
          : rows.isEmpty && r.ayahs.isEmpty
              ? _Message(l.searchNothing(_query.trim()))
              : ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: rows.length + r.ayahs.length,
                  itemBuilder: (context, i) {
                    if (i < rows.length) return rows[i];
                    final verse = r.ayahs[i - rows.length];
                    return PlaceTile(
                      title: verseReference(verse, names),
                      subtitle: verseLocation(l, quran, verse.id),
                      verse: verse,
                      onTap: () => _open(verse.id),
                    );
                  },
                ),
    );
  }

  Widget _target(AppLocalizations l, SearchTarget t, Quran quran, SurahNames names) {
    final start = quran.verse(t.verseId);
    final (IconData icon, String title, String subtitle) = switch (t) {
      AyahTarget() => (Icons.format_quote_outlined, verseReference(start, names), verseLocation(l, quran, t.verseId)),
      SurahTarget(:final surah) => (
          Icons.menu_book_outlined,
          // In Arabic the display name is the Arabic name: say it once.
          names.isArabic ? names.of(surah) : '${names.of(surah)} · ${quran.surah(surah).nameAr}',
          l.surahNumberAyahs(surah, l.ayahCount(quran.surah(surah).ayahCount)),
        ),
      JuzTarget(:final juz) => (
          Icons.bookmarks_outlined,
          l.juzNumber(juz),
          l.fromPlacePage(verseReference(start, names), quran.pageOf(t.verseId)),
        ),
      PageTarget(:final page) => (
          Icons.description_outlined,
          l.pageNumber(page),
          l.fromPlaceJuz(verseReference(start, names), quran.juzOf(t.verseId)),
        ),
    };
    return PlaceTile(
      leading: Icon(icon),
      title: title,
      subtitle: subtitle,
      verse: t is AyahTarget ? start : null,
      onTap: () => _open(t.verseId),
    );
  }
}

class _Help extends StatelessWidget {
  const _Help();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final style = RubricText.label.copyWith(color: c.inkSecondary);
    return ListView(
      padding: const EdgeInsets.all(RubricSpace.s6),
      children: [
        Text(l.searchBy.toUpperCase(), style: RubricText.overlineFor(context).copyWith(color: c.inkSecondary)),
        const SizedBox(height: RubricSpace.s2),
        Text(l.searchHelpSurah, style: style),
        Text(l.searchHelpAyah, style: style),
        Text(l.searchHelpPlace, style: style),
        Text(l.searchHelpWords, style: style),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(RubricSpace.s6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: RubricText.label.copyWith(color: context.colors.inkSecondary),
        ),
      );
}
