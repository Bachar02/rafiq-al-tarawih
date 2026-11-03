import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/recognition/models.dart';
import '../../data/quran.dart';
import '../settings/settings_screen.dart';
import 'display_status.dart';
import 'listen_state.dart';
import 'widgets/ayah_actions.dart';
import 'widgets/hint_sheet.dart';
import 'widgets/mic_button.dart';
import 'widgets/now_card.dart';
import 'widgets/mushaf_view.dart';
import 'widgets/session_banner.dart';
import 'widgets/surah_index.dart';

/// The whole app on one screen: tap, and follow the imam.
class ListenScreen extends ConsumerStatefulWidget {
  const ListenScreen({super.key});

  @override
  ConsumerState<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends ConsumerState<ListenScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // The OS will not keep the microphone for a backgrounded app anyway; stop
    // cleanly and say so, instead of silently showing a stale ayah.
    if (lifecycle == AppLifecycleState.paused) ref.read(listenControllerProvider.notifier).pause();
  }

  void _toggle(ListenState state) {
    final controller = ref.read(listenControllerProvider.notifier);
    state.isActive ? controller.stop() : controller.start();
  }

  Future<void> _openSettings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

  Future<void> _chooseHint(ListenState state) async {
    final choice = await showHintSheet(context, quran: ref.read(quranProvider), current: state.hint);
    if (choice != null) await ref.read(listenControllerProvider.notifier).setHint(choice.hint);
  }

  Future<void> _openIndex(ListenState state) async {
    final surah = await showSurahIndex(context, quran: ref.read(quranProvider), current: state.readerSurah);
    if (surah != null) ref.read(listenControllerProvider.notifier).browse(surah);
  }

  /// Tapping an ayah: "the imam is here", or lock/unlock the surah.
  Future<void> _onAyahTap(Verse verse, ListenState state) async {
    final controller = ref.read(listenControllerProvider.notifier);
    final action = await showAyahActions(
      context,
      verse: verse,
      quran: ref.read(quranProvider),
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(listenControllerProvider);
    final settings = ref.watch(settingsProvider);
    final quran = ref.watch(quranProvider);
    final status = DisplayStatus.of(state);
    final shown = state.track.showing;
    final reader = state.readerSurah;
    final controller = ref.read(listenControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('رفيق', style: TextStyle(fontFamily: quranFont, fontSize: 26, color: context.scheme.primary)),
            const SizedBox(width: 8),
            // The Latin name yields first on narrow screens (three actions on the right).
            Flexible(
              child: Text(
                'Rafiq',
                overflow: TextOverflow.fade,
                softWrap: false,
                style: context.text.titleMedium?.copyWith(color: context.colors.muted),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Surahs',
            onPressed: () => _openIndex(state),
            icon: const Icon(Icons.menu_book_outlined),
          ),
          IconButton(
            tooltip: 'Help the app (hint)',
            onPressed: () => _chooseHint(state),
            icon: Icon(state.hint == null ? Icons.tune_rounded : Icons.tune,
                color: state.hint == null ? null : context.scheme.primary),
          ),
          IconButton(tooltip: 'Settings', onPressed: _openSettings, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: NowCard(
                state: state,
                quran: quran,
                onLock: reader == null ? null : () => controller.lockTo(SurahHint(reader)),
                onUnlock: controller.unlock,
              ),
            ),
            // Everything between the status card and the mic shares one
            // flexible region, so nothing overflows on small screens or with
            // large system fonts: the surah text gives way first.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.track.alternatives.isNotEmpty && state.isActive)
                    _Notice(
                      icon: Icons.call_split_rounded,
                      text: 'Repeated text — could also be ${state.track.alternatives.map((p) => p.ref).join(' · ')}',
                      color: context.colors.uncertain,
                    ),
                  if (state.warning != null)
                    _Notice(icon: Icons.info_outline, text: state.warning!, color: context.colors.uncertain),
                  if (state.browsing && state.isActive)
                    _FollowBar(
                      imamSurah: shown == null ? null : quran.surah(shown.surah),
                      onFollow: controller.followImam,
                    ),
                  if (state.phase == SessionPhase.failed && state.error != null)
                    // Takes the space it needs (up to most of the region): when
                    // something is wrong, fixing it matters more than the text.
                    Flexible(
                      flex: 6,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: ErrorPanel(
                          error: state.error!,
                          message: state.errorMessage ?? '',
                          onRetry: controller.start,
                          onOpenSettings: _openSettings,
                          onDismiss: controller.dismissError,
                        ),
                      ),
                    ),
                  Expanded(
                    flex: 2,
                    child: reader == null
                        ? _EmptyState(status: status)
                        : MushafView(
                            quran: quran,
                            surah: reader,
                            current: shown,
                            confident: status.confident,
                            textScale: settings.textScale,
                            onAyahTap: (verse) => _onAyahTap(verse, state),
                            onOpenSurah: controller.browse,
                          ),
                  ),
                  if (settings.showDiagnostics)
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TranscriptPanel(state: state),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _BottomBar(
              state: state,
              status: status,
              onMic: () => _toggle(state),
              onHint: () => _chooseHint(state),
              onClearHint: () => controller.setHint(null),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({
    required this.state,
    required this.status,
    required this.onMic,
    required this.onHint,
    required this.onClearHint,
  });

  final ListenState state;
  final DisplayStatus status;
  final VoidCallback onMic;
  final VoidCallback onHint;
  final VoidCallback onClearHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = state.hint;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint != null)
            InputChip(
              avatar: const Icon(Icons.tune, size: 16),
              label: Text(hintLabel(hint, ref.read(quranProvider))),
              onPressed: onHint,
              onDeleted: onClearHint,
              deleteButtonTooltipMessage: 'Remove hint',
            ),
          MicButton(status: status, level: state.level, onPressed: onMic),
        ],
      ),
    );
  }
}

/// Shown while the user browses away from the imam's surah.
class _FollowBar extends StatelessWidget {
  const _FollowBar({required this.imamSurah, required this.onFollow});

  final Surah? imamSurah;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: [
            Icon(Icons.menu_book_outlined, size: 16, color: context.colors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                imamSurah == null ? 'Browsing' : 'Browsing · the imam is in ${imamSurah!.nameTranslit}',
                style: context.text.bodySmall?.copyWith(color: context.colors.muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: onFollow,
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text('Follow the imam'),
            ),
          ],
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: context.text.bodySmall?.copyWith(color: color))),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.status});

  final DisplayStatus status;

  @override
  Widget build(BuildContext context) {
    final listening = status == DisplayStatus.searching || status == DisplayStatus.connecting;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'بِسْمِ اللَّهِ',
              textDirection: TextDirection.rtl,
              // Amiri's diacritics reach far below the baseline: give them room.
              style: TextStyle(
                fontFamily: quranFont,
                fontSize: 40,
                height: 1.8,
                color: context.colors.muted.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              listening
                  ? 'Keep the phone where it can hear the imam. The surah appears after a few words.'
                  : 'Rafiq listens to the imam and shows you the surah and ayah, live. No setup needed.',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(color: context.colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
