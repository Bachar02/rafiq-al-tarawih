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
import '../../data/study_text.dart';
import 'share_ayah_sheet.dart';
import '../notes/note_sheet.dart';
import 'package:flutter/services.dart';
import '../../app/navigation.dart';
import 'widgets/page_scrubber.dart';
import 'widgets/return_button.dart';

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

  /// What decides whether the reader is in view (and reading time runs).
  bool _appShown = true, _tabShown = true, _routeShown = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _appShown = state == null || state == AppLifecycleState.resumed;
    _tabShown = ref.read(homeTabProvider) == HomeTab.read;
    ref
        .read(readingSessionProvider.notifier)
        .showPage(ref.read(quranProvider).pageOf(ref.read(readingPositionProvider)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A route or sheet over the reader (settings, Taraweeh, an ayah's sheet).
    _routeShown = ModalRoute.of(context)?.isCurrent ?? true;
    _syncVisible();
  }

  /// Tell the reading session whether the text is in view, after this frame
  /// (providers are not changed while widgets build).
  void _syncVisible() {
    final visible = _appShown && _tabShown && _routeShown;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(readingSessionProvider.notifier).setVisible(visible);
    });
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
    final session = ref.read(readingSessionProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      _appShown = true;
      session.appResumed();
    } else {
      _appShown = false;
      unawaited(ref.read(readingPositionProvider.notifier).flush());
      if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) session.appPaused();
    }
    _syncVisible();
  }

  /// Open the text at [verseId] and mark it for a moment, so the eye finds it.
  /// A jump [from] another place offers the way back there.
  void openAt(int verseId, {bool mark = true, ReaderOrigin? from}) {
    if (from != null) {
      ref.read(readerReturnProvider.notifier).set(ReaderReturn(
            to: from,
            previousVerse: ref.read(readingPositionProvider),
            landedPage: ref.read(quranProvider).pageOf(verseId),
          ));
    }
    if (_layout == ReadingLayout.pages) {
      _pages.jumpToVerse(verseId);
    } else {
      _view.jumpToVerse(verseId);
    }
    ref.read(readingPositionProvider.notifier).update(verseId);
    ref.read(readingSessionProvider.notifier).showPage(ref.read(quranProvider).pageOf(verseId));
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

  Future<void> _search({String query = ''}) async {
    final choice = await AppRoutes.search(context, query: query);
    if (choice != null && mounted) openAt(choice.verseId, from: SearchOrigin(choice.query));
  }

  /// Back to where the last jump came from (the button, or the phone's back).
  /// If the user only looked (still on the page the jump landed on), the
  /// reading position goes back to where it was.
  void _goBack() {
    final back = ref.read(readerReturnProvider);
    if (back == null) return;
    ref.read(readerReturnProvider.notifier).clear();
    final quran = ref.read(quranProvider);
    if (quran.pageOf(ref.read(readingPositionProvider)) == back.landedPage) openAt(back.previousVerse, mark: false);
    final tabs = ref.read(homeTabProvider.notifier);
    switch (back.to) {
      case TabOrigin(:final tab, :final view):
        if (view != null) ref.read(bookmarksViewProvider.notifier).select(view);
        tabs.select(tab);
      case KhatmOrigin(:final tab):
        tabs.select(tab);
        unawaited(AppRoutes.khatm(context));
      case SearchOrigin(:final query):
        unawaited(_search(query: query));
    }
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
      noted: ref.read(notesProvider.notifier).noteFor(verse.id) != null,
      // Taraweeh has been followed, and this is not already where it stopped.
      offerTaraweehEnd:
          ref.read(taraweehLedgerProvider).nights.isNotEmpty && ref.read(taraweehPositionProvider)?.verseId != verse.id,
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
      case ReaderAyahAction.note:
        await editNote(context, ref, verse);
      case ReaderAyahAction.share:
        await showShareAyahSheet(context, verse: verse, names: names);
      case ReaderAyahAction.copy:
        await copyAyah(verse, names);
        say(l.copied(ref_));
      case ReaderAyahAction.translation:
        await AppRoutes.study(context, verseId: verse.id);
      case ReaderAyahAction.tafsir:
        await AppRoutes.study(context, verseId: verse.id, kind: StudyKind.tafsir);
      case ReaderAyahAction.taraweehEnded:
        final progress = ref.read(taraweehLedgerProvider.notifier);
        final before = progress.correct(verse.id, ref.read(clockProvider)());
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(l.taraweehEndSet(ref_)),
            action: SnackBarAction(label: l.undo, onPressed: () => progress.restore(before)),
          ));
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
    final session = ref.read(readingSessionProvider.notifier);
    final position = ref.read(readingPositionProvider.notifier);
    final bookmarked = {for (final b in ref.watch(bookmarksProvider)) b.verseId};
    final noted = {for (final n in ref.watch(notesProvider)) n.verseId};
    // The last page of a khatm was just read: say so, once, calmly.
    ref.listen(khatmProvider, (before, after) {
      if (before == null || after.finished.length <= before.finished.length) return;
      final l = context.l10n;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${l.khatmComplete} · ${l.khatmInDays(after.finished.first.days)}')));
    });
    // Reading time runs only while the Read tab is shown. Leaving the tab
    // ends the way back: the user has gone somewhere else.
    ref.listen(homeTabProvider, (_, tab) {
      _tabShown = tab == HomeTab.read;
      _syncVisible();
      if (!_tabShown) ref.read(readerReturnProvider.notifier).clear();
    });
    // Another tab asked for a place: open it here.
    ref.listen(readerRequestsProvider, (_, request) {
      if (request != null) openAt(request.verseId, mark: request.mark, from: request.from);
    });
    final back = ref.watch(readerReturnProvider);
    final bottomPadding = RubricSpace.s4 + (back == null ? 0 : 64);

    return PopScope(
      // With a way back, the phone's back button takes it.
      canPop: back == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
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
                              notedVerses: noted,
                              onAyahTap: _onAyahTap,
                              onAyahLongPress: _toggleBookmark,
                              onPageChanged: (page) {
                                position.update(quran.pages.start(page));
                                session.showPage(page);
                                _moved();
                              },
                              onUserScroll: (_) => _moved(),
                              bottomPadding: bottomPadding,
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
                              notedVerses: noted,
                              onAyahTap: _onAyahTap,
                              onAyahLongPress: _toggleBookmark,
                              onTopVerseChanged: (verse) {
                                position.update(verse);
                                session.showPage(quran.pageOf(verse));
                                _moved();
                              },
                              bottomPadding: bottomPadding,
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
                    if (back != null)
                      Positioned(
                        left: RubricSpace.gutter,
                        right: RubricSpace.gutter,
                        bottom: RubricSpace.s3,
                        child: Center(child: ReaderReturnButton(to: back.to, onTap: _goBack)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
