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

  /// Read once: afterwards the view owns its scroll position.
  late final int _initialVerse = ref.read(readingPositionProvider);

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
    _view.jumpToVerse(verseId);
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
    void say(String text) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    final ref_ = '${names.of(verse.surah)} ${verse.surah}:${verse.ayah}';
    switch (action) {
      case ReaderAyahAction.bookmark:
        say(await bookmarks.add(verse.id) ? 'Bookmarked $ref_' : 'Could not save the bookmark. Try again.');
      case ReaderAyahAction.removeBookmark:
        say(await bookmarks.remove(verse.id) ? 'Bookmark removed' : 'Could not remove the bookmark. Try again.');
      case ReaderAyahAction.copy:
        await copyAyah(verse, names);
        say('Copied $ref_');
      case null:
        break;
    }
  }

  void _onUserScroll(ScrollDirection direction) {
    final visible = direction != ScrollDirection.reverse;
    if (visible != _entryVisible) setState(() => _entryVisible = visible);
  }

  @override
  Widget build(BuildContext context) {
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final textScale = ref.watch(settingsProvider.select((s) => s.textScale));
    final position = ref.read(readingPositionProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReaderBar(
              onNavigate: _navigate,
              onSearch: _search,
              onSettings: () => AppRoutes.settings(context),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: QuranView(
                      quran: quran,
                      names: names,
                      initialVerse: _initialVerse,
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
