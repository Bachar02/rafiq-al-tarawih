import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/place_tile.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';
import 'quran_search.dart';

/// Search the Quran: one field for references, pages, juz, surah names and
/// Arabic text. Pops with the chosen verse id.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _field = TextEditingController();
  String _query = '';
  SearchResults _results = SearchResults.empty;

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

  void _open(int verseId) => Navigator.of(context).pop(verseId);

  @override
  Widget build(BuildContext context) {
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final c = context.colors;
    final r = _results;

    final rows = <Widget>[
      if (r.textTooShort) _Message('Type at least ${QuranSearch.minLetters} letters to search the text.'),
      for (final t in r.targets) _target(t, quran, names),
      if (r.ayahs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(RubricSpace.s4, RubricSpace.s4, RubricSpace.s4, RubricSpace.s1),
          child: Text(
            // Overlines are Latin capitals (brand book §4).
            (r.ayahTotal > r.ayahs.length
                    ? 'First ${r.ayahs.length} of ${r.ayahTotal} ayahs'
                    : '${r.ayahTotal} ${r.ayahTotal == 1 ? 'ayah' : 'ayahs'}')
                .toUpperCase(),
            style: RubricText.overline.copyWith(color: c.inkSecondary),
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
              hintText: 'Surah, 2:255, page 50, or Arabic words',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
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
              ? _Message('Nothing found for “${_query.trim()}”.')
              : ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: rows.length + r.ayahs.length,
                  itemBuilder: (context, i) {
                    if (i < rows.length) return rows[i];
                    final verse = r.ayahs[i - rows.length];
                    return PlaceTile(
                      title: verseReference(verse, names),
                      subtitle: verseLocation(quran, verse.id),
                      verse: verse,
                      onTap: () => _open(verse.id),
                    );
                  },
                ),
    );
  }

  Widget _target(SearchTarget t, Quran quran, SurahNames names) {
    final start = quran.verse(t.verseId);
    final (IconData icon, String title, String subtitle) = switch (t) {
      AyahTarget() => (Icons.format_quote_outlined, verseReference(start, names), verseLocation(quran, t.verseId)),
      SurahTarget(:final surah) => (
          Icons.menu_book_outlined,
          '${names.of(surah)} · ${quran.surah(surah).nameAr}',
          'Surah $surah · ${quran.surah(surah).ayahCount} ayahs',
        ),
      JuzTarget(:final juz) => (
          Icons.bookmarks_outlined,
          'Juz $juz',
          'From ${verseReference(start, names)} · Page ${quran.pageOf(t.verseId)}',
        ),
      PageTarget(:final page) => (
          Icons.description_outlined,
          'Page $page',
          'From ${verseReference(start, names)} · Juz ${quran.juzOf(t.verseId)}',
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
    final style = RubricText.label.copyWith(color: c.inkSecondary);
    return ListView(
      padding: const EdgeInsets.all(RubricSpace.s6),
      children: [
        Text('SEARCH BY', style: RubricText.overline.copyWith(color: c.inkSecondary)),
        const SizedBox(height: RubricSpace.s2),
        Text('A surah: Al-Kahf, الكهف, or 18', style: style),
        Text('An ayah: 2:255', style: style),
        Text('A page or juz: page 50, juz 30', style: style),
        Text('Words of the Quran, in Arabic: ٱلْحَمْدُ لِلَّهِ (with or without tashkeel)', style: style),
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
