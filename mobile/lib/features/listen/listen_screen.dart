import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/components/notice.dart';
import '../../app/components/wordmark.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/recognition/models.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';
import '../settings/settings_screen.dart';
import 'display_status.dart';
import 'listen_state.dart';
import 'widgets/ayah_actions.dart';
import 'widgets/diagnostics_panel.dart';
import 'widgets/hint_sheet.dart';
import 'widgets/listen_control.dart';
import 'widgets/position_header.dart';
import 'widgets/quran_column.dart';
import 'widgets/return_to_imam.dart';
import 'widgets/status_line.dart';
import 'widgets/surah_index.dart';

/// The whole app on one screen: tap, and follow the imam.
///
/// Top to bottom (brand book §6a): wordmark and header controls · position
/// header · status line · Quran column · notices · mic level · listen control.
class ListenScreen extends ConsumerStatefulWidget {
  const ListenScreen({super.key});

  @override
  ConsumerState<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends ConsumerState<ListenScreen> with WidgetsBindingObserver {
  final _column = GlobalKey<QuranColumnState>();

  /// The user scrolled the current ayah out of view.
  bool _away = false;

  /// Re-evaluates the time-based states (Little sound, No new match yet)
  /// while a session runs, even when no event arrives.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // The OS will not keep the microphone for a backgrounded app anyway; stop
    // cleanly and say so, instead of silently showing a stale ayah.
    if (lifecycle == AppLifecycleState.paused) ref.read(listenControllerProvider.notifier).pause();
  }

  void _runClock(bool active) {
    _clock?.cancel();
    _clock = active ? Timer.periodic(const Duration(seconds: 1), (_) => setState(() {})) : null;
  }

  void _toggle(DisplayStatus status) {
    final controller = ref.read(listenControllerProvider.notifier);
    status.active ? controller.stop() : controller.start();
  }

  Future<void> _openSettings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  Future<void> _chooseHint(ListenState state) async {
    final choice = await showHintSheet(
      context,
      quran: ref.read(quranProvider),
      names: ref.read(surahNamesProvider),
      current: state.hint,
      active: state.isActive,
    );
    if (choice != null) await ref.read(listenControllerProvider.notifier).setHint(choice.hint);
  }

  Future<void> _openIndex(ListenState state) async {
    final surah = await showSurahIndex(
      context,
      quran: ref.read(quranProvider),
      names: ref.read(surahNamesProvider),
      current: state.readerSurah,
    );
    if (surah != null) ref.read(listenControllerProvider.notifier).browse(surah);
  }

  /// Lock to the imam's surah (after a confirming sheet), or unlock.
  Future<void> _toggleLock(ListenState state) async {
    final controller = ref.read(listenControllerProvider.notifier);
    if (state.lock != null) {
      controller.unlock();
      return;
    }
    final surah = state.displayed?.surah ?? state.readerSurah;
    if (surah == null) return;
    final lock = await showLockSheet(context, surahName: ref.read(surahNamesProvider).of(surah));
    if (lock == true) controller.lockTo(SurahHint(surah));
  }

  /// Tapping an ayah: "the imam is here", or lock/unlock the surah.
  Future<void> _onAyahTap(Verse verse, ListenState state) async {
    final controller = ref.read(listenControllerProvider.notifier);
    final action = await showAyahActions(
      context,
      verse: verse,
      quran: ref.read(quranProvider),
      names: ref.read(surahNamesProvider),
      listening: state.isActive,
      lock: state.lock,
    );
    switch (action) {
      case AyahAction.imamIsHere:
        controller.setPosition(Position(verseId: verse.id, surah: verse.surah, ayah: verse.ayah));
      case AyahAction.lockSurah:
        controller.lockTo(SurahHint(verse.surah));
      case AyahAction.unlock:
        controller.unlock();
      case null:
        break;
    }
  }

  void _returnToImam(ListenState state) {
    if (state.browsing) ref.read(listenControllerProvider.notifier).followImam();
    _column.currentState?.returnToImam();
    setState(() => _away = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(listenControllerProvider.select((s) => s.isActive), (_, active) => _runClock(active));
    final state = ref.watch(listenControllerProvider);
    final settings = ref.watch(settingsProvider);
    final quran = ref.watch(quranProvider);
    final names = ref.watch(surahNamesProvider);
    final now = DateTime.now();
    final status = DisplayStatus.of(state, now);
    final displayed = state.displayed;
    final reader = state.readerSurah;
    final controller = ref.read(listenControllerProvider.notifier);
    final sure = status.marker(held: displayed != null) == MarkerFill.filled;
    final showReturn = status.active && displayed != null && (state.browsing || _away);
    final hearing =
        state.lastSoundAt != null && now.difference(state.lastSoundAt!) < const Duration(milliseconds: 1500);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, screen) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(
                state: state,
                status: status,
                names: names,
                onHint: () => _chooseHint(state),
                onLock: () => _toggleLock(state),
                onSettings: _openSettings,
              ),
              // On a small phone with large system text, the header and status
              // scroll within 40% of the screen rather than push the Quran
              // column and the control off it.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: screen.maxHeight * 0.4),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s2, RubricSpace.gutter, 0),
                        child: PositionHeader(
                          position: displayed,
                          quran: quran,
                          names: names,
                          unsure: status.engineUnsure,
                          onOpenSurahs: () => _openIndex(state),
                        ),
                      ),
                      const SizedBox(height: RubricSpace.s4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: RubricSpace.gutter),
                        child: StatusLine(
                          status: status,
                          held: displayed != null,
                          ayah: displayed?.ayah,
                          reconnectAttempt: state.reconnectAttempt,
                          note: state.track.alternatives.isNotEmpty && state.isActive
                              ? 'Repeated text — could also be ${state.track.alternatives.map((p) => p.ref).join(' · ')}'
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: RubricSpace.s6),
              // Everything between the status line and the control shares one
              // flexible region: the Quran column gives way first on small
              // screens or with large system fonts.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, region) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: RubricSpace.gutter),
                                child: reader == null
                                    ? _EmptyColumn(status: status, onBrowse: () => _openIndex(state))
                                    : QuranColumn(
                                        key: _column,
                                        quran: quran,
                                        names: names,
                                        surah: reader,
                                        current: displayed,
                                        unsure: status.engineUnsure,
                                        showTitle: displayed?.surah != reader,
                                        textScale: settings.textScale,
                                        bottomPadding: showReturn ? 72 : 0,
                                        onAyahTap: (verse) => _onAyahTap(verse, state),
                                        onOpenSurah: controller.browse,
                                        onAwayChanged: (away) => setState(() => _away = away),
                                      ),
                              ),
                            ),
                            Positioned(
                              left: RubricSpace.gutter,
                              right: RubricSpace.gutter,
                              bottom: RubricSpace.s4,
                              child: Center(
                                child: ReturnToImam(
                                  visible: showReturn,
                                  position: displayed,
                                  sure: sure,
                                  onTap: () => _returnToImam(state),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Directly above the control, never over the Quran column.
                      // Fixing what stopped the session matters more than the
                      // text, so a long notice takes up to 60% of the region.
                      if (state.warning != null || _Notices.has(status, state))
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: region.maxHeight * 0.6),
                          child: SingleChildScrollView(
                            padding:
                                const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s3, RubricSpace.gutter, 0),
                            child: _Notices(
                              state: state,
                              status: status,
                              onRetry: controller.start,
                              onDismiss: controller.dismissError,
                              onOpenSettings: _openSettings,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (settings.showDiagnostics)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s2, RubricSpace.gutter, 0),
                    child: TranscriptPanel(state: state),
                  ),
                ),
              _Bottom(
                state: state,
                status: status,
                names: names,
                hearing: hearing,
                onToggle: () => _toggle(status),
                onHint: () => _chooseHint(state),
                onClearHint: () => controller.setHint(null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Monochrome wordmark and one context control plus settings. Before
/// following, the hint is offered; while following the hint no longer helps
/// the engine, so the surah lock takes its place.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.status,
    required this.names,
    required this.onHint,
    required this.onLock,
    required this.onSettings,
  });

  final ListenState state;
  final DisplayStatus status;
  final SurahNames names;
  final VoidCallback onHint;
  final VoidCallback onLock;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lock = state.lock;
    final showLock = lock != null || (status.active && state.displayed != null);
    final lockLabel = switch (lock) {
      SurahHint(:final surah) => names.of(surah),
      JuzHint(:final juz) => 'Juz $juz',
      null => null,
    };
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(RubricSpace.gutter, RubricSpace.s2, RubricSpace.s3, 0),
      child: Row(
        children: [
          const Wordmark(),
          const Spacer(),
          if (showLock)
            IconButton(
              tooltip: lockLabel == null ? 'Stay on this surah' : 'Locked to $lockLabel. Tap to unlock.',
              onPressed: onLock,
              isSelected: lock != null,
              icon: const Icon(Icons.lock_open_outlined),
              selectedIcon: Icon(Icons.lock_outline, color: c.ink),
            )
          else
            IconButton(
              tooltip: "Tonight's starting point",
              onPressed: onHint,
              isSelected: state.hint != null,
              icon: const Icon(Icons.format_list_bulleted),
              selectedIcon: Icon(Icons.format_list_bulleted, color: c.ink),
            ),
          IconButton(tooltip: 'Settings', onPressed: onSettings, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
    );
  }
}

/// The mic level or the hint, and the listen control.
class _Bottom extends StatelessWidget {
  const _Bottom({
    required this.state,
    required this.status,
    required this.names,
    required this.hearing,
    required this.onToggle,
    required this.onHint,
    required this.onClearHint,
  });

  final ListenState state;
  final DisplayStatus status;
  final SurahNames names;
  final bool hearing;
  final VoidCallback onToggle;
  final VoidCallback onHint;
  final VoidCallback onClearHint;

  @override
  Widget build(BuildContext context) {
    final hint = state.hint;
    return Padding(
      padding: const EdgeInsets.fromLTRB(RubricSpace.gutter, RubricSpace.s3, RubricSpace.gutter, RubricSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status.active && status != DisplayStatus.stopping)
            Padding(
              padding: const EdgeInsets.only(bottom: RubricSpace.s3),
              child: MicLevel(level: state.level, hearing: hearing),
            )
          else if (hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: RubricSpace.s3),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: _HintChip(label: hintLabel(hint, names), onTap: onHint, onClear: onClearHint),
              ),
            ),
          ListenControl(status: status, onPressed: onToggle),
        ],
      ),
    );
  }
}

/// A transient engine warning, and the Notice for a stopped or blocked
/// session, mapped from the app's real errors.
class _Notices extends StatelessWidget {
  const _Notices({
    required this.state,
    required this.status,
    required this.onRetry,
    required this.onDismiss,
    required this.onOpenSettings,
  });

  final ListenState state;
  final DisplayStatus status;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;
  final VoidCallback onOpenSettings;

  static bool has(DisplayStatus status, ListenState state) =>
      status == DisplayStatus.paused || (status == DisplayStatus.failed && state.error != null);

  @override
  Widget build(BuildContext context) {
    final notice = _notice();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.warning != null) Notice(icon: Icons.info_outline, title: state.warning!),
        if (state.warning != null && notice != null) const SizedBox(height: RubricSpace.s2),
        if (notice != null) notice,
      ],
    );
  }

  Widget? _notice() {
    if (status == DisplayStatus.paused) {
      return Notice(
        icon: Icons.info_outline,
        title: 'Following paused',
        body: 'The app went to the background. The last position stays on screen.',
        actionLabel: 'Resume',
        onAction: onRetry,
      );
    }
    final error = state.error;
    if (status != DisplayStatus.failed || error == null) return null;
    final message = state.errorMessage ?? '';
    return switch (error) {
      ListenError.micPermission => Notice(
          icon: Icons.mic_off_outlined,
          title: 'Rafiq needs the microphone',
          body: "It listens to the imam's recitation to find the ayah. If you denied it before, allow it in your "
              'phone settings: Apps → Rafiq → Permissions → Microphone.',
          actionLabel: 'Try again',
          onAction: onRetry,
          onDismiss: onDismiss,
          alert: true,
        ),
      ListenError.microphone => Notice(
          icon: Icons.mic_off_outlined,
          title: 'The microphone stopped working',
          body: message,
          actionLabel: 'Try again',
          onAction: onRetry,
          onDismiss: onDismiss,
          alert: true,
        ),
      // Server build only: removed with on-device recognition.
      ListenError.unreachable => Notice(
          icon: Icons.wifi_off_outlined,
          title: "Can't reach the recognition server",
          body: "This build recognises on a computer on the same Wi-Fi. Check that it's running and that the "
              'address in Settings is right.',
          actionLabel: 'Test connection',
          onAction: onOpenSettings,
          onDismiss: onDismiss,
          alert: true,
        ),
      ListenError.server => Notice(
          icon: Icons.info_outline,
          title: 'Recognition stopped',
          body: message,
          actionLabel: 'Try again',
          onAction: onRetry,
          onDismiss: onDismiss,
          alert: true,
        ),
    };
  }
}

/// "Tonight: Juz 30", shown while not following; tap to change, × to remove.
class _HintChip extends StatelessWidget {
  const _HintChip({required this.label, required this.onTap, required this.onClear});

  final String label;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(RubricRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: RubricSpace.s3),
              child: Text(label, style: RubricText.label.copyWith(color: c.ink)),
            ),
          ),
          IconButton(
            tooltip: 'Remove hint',
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Before any position: a quiet explanation, and a way to browse.
class _EmptyColumn extends StatelessWidget {
  const _EmptyColumn({required this.status, required this.onBrowse});

  final DisplayStatus status;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final listening = status.active;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: RubricSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              listening
                  ? 'Keep the phone where it can hear the imam.'
                  : 'Rafiq listens to the imam and shows the surah and ayah, live.',
              textAlign: TextAlign.center,
              style: RubricText.label.copyWith(color: c.inkSecondary),
            ),
            const SizedBox(height: RubricSpace.s2),
            TextButton.icon(
              onPressed: onBrowse,
              style: TextButton.styleFrom(foregroundColor: c.inkSecondary),
              icon: const Icon(Icons.menu_book_outlined, size: 20),
              label: const Text('Browse surahs'),
            ),
          ],
        ),
      ),
    );
  }
}
