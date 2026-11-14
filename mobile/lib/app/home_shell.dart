import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/bookmarks/bookmarks_screen.dart';
import '../features/more/more_screen.dart';
import '../features/navigate/navigate_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/reader/reading_review_sheet.dart';
import '../l10n/l10n.dart';
import '../services/reminders.dart' show dhikrPayload, isAdhanPayload, readingPayload;
import 'navigation.dart';
import 'providers.dart';
import 'routes.dart';

/// The app's frame: a labelled bar at the bottom. Read · Surahs · Bookmarks ·
/// Taraweeh · More.
///
/// The reader is always alive underneath (its place and scroll survive a
/// visit elsewhere); the other tabs are built fresh on each visit, so their
/// lists open at the current place. Taraweeh is a button, not a tab: it opens
/// the full-screen mode and starts listening. Back from any tab returns to
/// the reader; back from the reader leaves the app.
///
/// When a reading session is over (the app opens on pages read last time,
/// or comes back after a while), the shell asks the user to count them.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  /// Bar positions; Taraweeh sits between Bookmarks and More.
  static const _taraweeh = 3;

  static int _indexOf(HomeTab tab) => switch (tab) {
        HomeTab.read => 0,
        HomeTab.surahs => 1,
        HomeTab.bookmarks => 2,
        HomeTab.more => 4,
      };

  bool _reviewing = false;

  /// The daily reminders are rescheduled whenever the app is shown or
  /// hidden: their text (today's target, where to continue) stays true, and
  /// a day already read gets none. Dhikr reminders move their two weeks on,
  /// and the adhans their month.
  late final AppLifecycleListener _lifecycle;

  void _syncReminders() {
    ref.read(reminderSyncProvider).sync();
    ref.read(dhikrSyncProvider).sync();
    ref.read(adhanSyncProvider).sync();
  }

  /// On screen again, perhaps in another town: a place that came from the
  /// phone's location follows it (which schedules the adhans again).
  void _shown() {
    _syncReminders();
    ref.read(prayerSettingsProvider.notifier).followLocation();
  }

  /// A reading reminder tapped (or one that launched the app): the reader,
  /// where the user left off ([resumeVerseProvider]: the khatm's place), the
  /// ayah marked. Screens opened over it close; Taraweeh mode, and a sheet
  /// such as the reading review, stay.
  /// A dhikr reminder: the adhkar.
  /// An adhan: the prayer times, once (a second tap finds them open).
  void _opened(String payload) {
    if (!mounted) return;
    if (payload == readingPayload) {
      Navigator.of(context).popUntil(
        (route) => route.isFirst || route is PopupRoute || route.settings.name == AppRoutes.taraweehName,
      );
      ref.read(readerRequestsProvider.notifier).open(ref.read(resumeVerseProvider), mark: true);
    } else if (payload == dhikrPayload) {
      AppRoutes.adhkar(context);
    } else if (isAdhanPayload(payload)) {
      Navigator.of(context).popUntil((route) => route.settings.name != AppRoutes.prayerName);
      AppRoutes.prayer(context);
    }
  }

  Future<void> _listenForTaps() async {
    try {
      await ref.read(remindersProvider).onOpen(_opened);
    } catch (e, stack) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'reminders'));
    }
  }

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onShow: _shown, onHide: _syncReminders);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shown();
      _listenForTaps();
    });
    // Pages left from last time: ask once the app is on screen.
    if (ref.read(readingSessionProvider).ask > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _review());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Ask about the waiting pages, unless something else is on top (Taraweeh
  /// mode, a sheet): then the next session end asks.
  Future<void> _review() async {
    if (!mounted || _reviewing || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _reviewing = true;
    await showReadingReview(context, ref);
    _reviewing = false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(readingSessionProvider.select((s) => s.ask), (_, __) => _review());
    final l = context.l10n;
    final tab = ref.watch(homeTabProvider);
    final tabs = ref.read(homeTabProvider.notifier);

    return PopScope(
      canPop: tab == HomeTab.read,
      onPopInvokedWithResult: (didPop, _) {
        // On the Read tab, the reader's way back (if any) handles it.
        if (!didPop && tab != HomeTab.read) tabs.select(HomeTab.read);
      },
      child: Scaffold(
        body: Stack(
          children: [
            Offstage(
              offstage: tab != HomeTab.read,
              child: TickerMode(enabled: tab == HomeTab.read, child: const ReaderScreen()),
            ),
            if (tab == HomeTab.surahs) const _SurahsTab(),
            if (tab == HomeTab.bookmarks) const BookmarksScreen(),
            if (tab == HomeTab.more) const MoreScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _indexOf(tab),
          onDestinationSelected: (i) => switch (i) {
            0 => tabs.select(HomeTab.read),
            1 => tabs.select(HomeTab.surahs),
            2 => tabs.select(HomeTab.bookmarks),
            _taraweeh => AppRoutes.taraweeh(context),
            _ => tabs.select(HomeTab.more),
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.menu_book_outlined),
              selectedIcon: const Icon(Icons.menu_book),
              label: l.navRead,
            ),
            NavigationDestination(
              icon: const Icon(Icons.format_list_bulleted),
              label: l.navSurahs,
            ),
            NavigationDestination(
              icon: const Icon(Icons.bookmarks_outlined),
              selectedIcon: const Icon(Icons.bookmarks),
              label: l.navBookmarks,
            ),
            NavigationDestination(
              icon: const Icon(Icons.mic_none),
              label: l.taraweeh,
              tooltip: l.semTaraweehEntry,
            ),
            NavigationDestination(
              icon: const Icon(Icons.more_horiz),
              label: l.navMore,
            ),
          ],
        ),
      ),
    );
  }
}

/// The Surahs tab: the index, opening the chosen place in the reader.
class _SurahsTab extends ConsumerWidget {
  const _SurahsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false, title: Text(context.l10n.navSurahs)),
        body: QuranIndex(
          current: ref.read(readingPositionProvider),
          onOpen: (verse) =>
              ref.read(readerRequestsProvider.notifier).open(verse, from: const TabOrigin(HomeTab.surahs)),
        ),
      );
}
