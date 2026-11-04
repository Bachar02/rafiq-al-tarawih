import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../data/quran.dart';
import '../quran_view/quran_view.dart';
import 'reader_ayah_sheet.dart';
import 'widgets/reader_bar.dart';
import 'widgets/taraweeh_entry.dart';
import '../../l10n/l10n.dart';
import '../quran_view/mushaf_page_view.dart';
import '../../data/settings.dart';
import 'share_ayah_sheet.dart';

/// Home: the Quran, open where the user stopped reading.
///
/// The text is the shared [QuranView]. The verse at its top is the personal
/// reading position (saved a moment after scrolling stops, and whenever the
/// app leaves the foreground). The bar above names the place; the Taraweeh
/// button floats over the text and steps aside while reading down.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});

  @override
  ConsumerState<ReaderScreen> createState() => ReaderScreenState();
}

class ReaderScreenState extends ConsumerState<ReaderScreen> with WidgetsBindingObserver {
  final _view = QuranViewController();
  final _pages = MushafPageController();

  /// The ayah the user chose (an open sheet acts on it, or a jump landed on it).
  int? _highlighted;
  Timer? _clearHighlight;

  bool _entryVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _clearHighlight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(ref.read(readingPositionProvider.notifier).flush());
  }

  /// Open the text at [verseId] and mark it for a moment, so the eye finds it.
  void openAt(int verseId, {bool mark = true}) {
    if (_layout == ReadingLayout.pages) {
      _pages.jumpToVerse(verseId);
    } else {
      _view.jumpToVerse(verseId);
    }
    ref.read(readingPositionProvider.notifier).update(verseId);
    if (!mark) return;
    _clearHighlight?.cancel();
    setState(() => _highlighted = verseId);
    _clearHighlight = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlighted = null);
    });
  }

  Future<void> _navigate() async {
    final verse = await AppRoutes.navigate(context, current: ref.read(readingPositionProvider));
    if (verse != null && mounted) openAt(verse, mark: false);
  }

  Future<void> _search() async {
    final verse = await AppRoutes.search(context);
    if (verse != null && mounted) openAt(verse);
  }

  Future<void> _onAyahTap(Verse verse) async {
    final names = ref.read(surahNamesProvider);
    final bookmarks = ref.read(bookmarksProvider.notifier);
    _clearHighlight?.cancel();
    setState(() => _highlighted = verse.id);
    final action = await showReaderAyahSheet(
      context,
      verse: verse,
      names: names,
      bookmarked: bookmarks.contains(verse.id),
    );
    if (!mounted) return;
    setState(() => _highlighted = null);
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    final ref_ = '${names.of(verse.surah)} ${verse.surah}:${verse.ayah}';
    switch (action) {
      case ReaderAyahAction.bookmark:
        say(await bookmarks.add(verse.id) ? l.bookmarked(ref_) : l.bookmarkFailed);
      case ReaderAyahAction.removeBookmark:
        say(await bookmarks.remove(verse.id) ? l.bookmarkRemoved : l.bookmarkRemoveFailed);
      case ReaderAyahAction.share:
        await showShareAyahSheet(context, verse: verse, names: names);
      case ReaderAyahAction.copy:
        await copyAyah(verse, names);
        say(l.copied(ref_));
      case null:
        break;
    }
  }

  ReadingLayout get _layout => ref.read(settingsProvider).readingLayout;

  void _toggleLayout() => ref.read(settingsProvider.notifier).update(
        (s) => s.copyWith(
            readingLayout: s.readingLayout == ReadingLayout.pages ? ReadingLayout.scroll : ReadingLayout.pages),
      );

  void _onUserScroll(ScrollDirection direction) {
    final visible = direction != ScrollDirection.reverse;
    if (visible != _entryVisible) setState(() => _entryVisible = visible);
  }

  @override
  Widget build(BuildContext context) {
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final textScale = ref.watch(settingsProvider.select((s) => s.textScale));
    final layout = ref.watch(settingsProvider.select((s) => s.readingLayout));
    // Each view opens where the other left off: the reading position is
    // read (not watched) when the view is created, then the view owns it.
    final opening = ref.read(readingPositionProvider);
    final position = ref.read(readingPositionProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReaderBar(
              onNavigate: _navigate,
              onToggleLayout: _toggleLayout,
              onSearch: _search,
              onSettings: () => AppRoutes.settings(context),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: layout == ReadingLayout.pages
                        ? MushafPageView(
                            key: const ValueKey(ReadingLayout.pages),
                            quran: quran,
                            names: names,
                            initialVerse: opening,
                            controller: _pages,
                            textScale: textScale,
                            highlightedVerse: _highlighted,
                            onAyahTap: _onAyahTap,
                            onPageChanged: (page) => position.update(quran.pages.start(page)),
                            onUserScroll: _onUserScroll,
                            bottomPadding: TaraweehEntry.height + RubricSpace.s4,
                          )
                        : QuranView(
                            key: const ValueKey(ReadingLayout.scroll),
                            quran: quran,
                            names: names,
                            initialVerse: opening,
                            controller: _view,
                            textScale: textScale,
                            highlightedVerse: _highlighted,
                            onAyahTap: _onAyahTap,
                            onTopVerseChanged: position.update,
                            onUserScroll: _onUserScroll,
                            bottomPadding: TaraweehEntry.height + RubricSpace.s4,
                          ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: RubricSpace.s4,
                    child: Center(
                      child: TaraweehEntry(
                        visible: _entryVisible,
                        onPressed: () => AppRoutes.taraweeh(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
