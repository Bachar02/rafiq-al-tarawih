import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../data/quran.dart';
import '../quran_view/quran_view.dart';
import 'reader_ayah_sheet.dart';
import 'widgets/reader_bar.dart';
import '../../l10n/l10n.dart';
import '../quran_view/mushaf_page_view.dart';
import '../../data/settings.dart';
import 'share_ayah_sheet.dart';
import 'package:flutter/services.dart';
import '../../app/navigation.dart';
import 'widgets/page_scrubber.dart';

/// The Read tab: the Quran, open where the user stopped reading.
///
/// The text is the shared [QuranView] (or the page view). The verse at its
/// top is the personal reading position (saved a moment after scrolling
/// stops, and whenever the app leaves the foreground). The bar above names
/// the place; a scrubber on the edge flies through the pages. Tap an ayah
/// for its sheet; press and hold to bookmark or un-bookmark it at once.
/// Other tabs open places here through [readerRequestsProvider].
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

  /// Pinged whenever the text moves: the scrubber shows.
  final _activity = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Opening the app is not reading the page it opens on.
    ref
        .read(readingProgressProvider.notifier)
        .jumpedTo(ref.read(quranProvider).pageOf(ref.read(readingPositionProvider)));
  }

  @override
  void dispose() {
    _clearHighlight?.cancel();
    _activity.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(ref.read(readingPositionProvider.notifier).flush());
      unawaited(ref.read(readingProgressProvider.notifier).flush());
      unawaited(ref.read(khatmProvider.notifier).flush());
    }
  }

  /// Open the text at [verseId] and mark it for a moment, so the eye finds it.
  void openAt(int verseId, {bool mark = true}) {
    // A jump is not reading: nothing between here and there counts.
    ref.read(readingProgressProvider.notifier).jumpedTo(ref.read(quranProvider).pageOf(verseId));
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

  /// The scrubber is over [page]: show its first ayah.
  void _scrubTo(int page) => openAt(ref.read(quranProvider).pages.start(page), mark: false);

  /// Press and hold: bookmark the ayah, or remove its bookmark, at once.
  Future<void> _toggleBookmark(Verse verse) async {
    final bookmarks = ref.read(bookmarksProvider.notifier);
    final names = ref.read(surahNamesProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    unawaited(HapticFeedback.selectionClick());
    final existing = ref.read(bookmarksProvider).where((b) => b.verseId == verse.id).firstOrNull;
    final reference = '${names.of(verse.surah)} ${verse.surah}:${verse.ayah}';
    if (existing != null) {
      final ok = await bookmarks.remove(verse.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(ok
            ? SnackBar(
                content: Text(l.bookmarkRemoved),
                action: SnackBarAction(label: l.undo, onPressed: () => bookmarks.restore(existing)),
              )
            : SnackBar(content: Text(l.bookmarkRemoveFailed)));
    } else {
      final ok = await bookmarks.add(verse.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(ok
            ? SnackBar(
                content: Text(l.bookmarked(reference)),
                action: SnackBarAction(label: l.undo, onPressed: () => bookmarks.remove(verse.id)),
              )
            : SnackBar(content: Text(l.bookmarkFailed)));
    }
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

  void _moved() => _activity.value++;

  @override
  Widget build(BuildContext context) {
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final textScale = ref.watch(settingsProvider.select((s) => s.textScale));
    final layout = ref.watch(settingsProvider.select((s) => s.readingLayout));
    // Each view opens where the other left off: the reading position is
    // read (not watched) when the view is created, then the view owns it.
    final opening = ref.read(readingPositionProvider);
    final progress = ref.read(readingProgressProvider.notifier);
    final position = ref.read(readingPositionProvider.notifier);
    final bookmarked = {for (final b in ref.watch(bookmarksProvider)) b.verseId};
    // The last page of a khatm was just read: say so, once, calmly.
    ref.listen(khatmProvider, (before, after) {
      if (before == null || after.finished.length <= before.finished.length) return;
      final l = context.l10n;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${l.khatmComplete} · ${l.khatmInDays(after.finished.first.days)}')));
    });
    // Another tab asked for a place: open it here.
    ref.listen(readerRequestsProvider, (_, request) {
      if (request != null) openAt(request.verseId, mark: request.mark);
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReaderBar(
              onOpenSurahs: () => ref.read(homeTabProvider.notifier).select(HomeTab.surahs),
              onToggleLayout: _toggleLayout,
              onSearch: _search,
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
                            bookmarkedVerses: bookmarked,
                            onAyahTap: _onAyahTap,
                            onAyahLongPress: _toggleBookmark,
                            onPageChanged: (page) {
                              position.update(quran.pages.start(page));
                              progress.movedTo(page);
                              _moved();
                            },
                            onUserScroll: (_) => _moved(),
                            bottomPadding: RubricSpace.s4,
                          )
                        : QuranView(
                            key: const ValueKey(ReadingLayout.scroll),
                            quran: quran,
                            names: names,
                            initialVerse: opening,
                            controller: _view,
                            textScale: textScale,
                            highlightedVerse: _highlighted,
                            bookmarkedVerses: bookmarked,
                            onAyahTap: _onAyahTap,
                            onAyahLongPress: _toggleBookmark,
                            onTopVerseChanged: (verse) {
                              position.update(verse);
                              progress.movedTo(quran.pageOf(verse));
                              _moved();
                            },
                            bottomPadding: RubricSpace.s4,
                          ),
                  ),
                  Positioned.fill(
                    child: Consumer(
                      // Only the scrubber follows the position as it moves.
                      builder: (context, ref, _) => PageScrubber(
                        quran: quran,
                        names: names,
                        page: quran.pageOf(ref.watch(readingPositionProvider)),
                        activity: _activity,
                        onScrub: _scrubTo,
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
