import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/recognition/models.dart';
import '../../../data/quran.dart';
import '../display_status.dart';
import '../listen_state.dart';

/// The answer to "where are we?": surah, ayah, and how sure the app is.
class NowCard extends StatelessWidget {
  const NowCard({super.key, required this.state, required this.quran, this.onLock, this.onUnlock});

  final ListenState state;
  final Quran quran;

  /// "This is the right surah" (null when there is no surah to lock to).
  final VoidCallback? onLock;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final status = DisplayStatus.of(state);
    final shown = state.track.showing;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: shown == null || status.confident ? 1 : 0.55,
              child: shown == null
                  ? _Placeholder(state: state, status: status, quran: quran)
                  : _Position(shown, quran, state),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Flexible(child: StatusChip(status: status, reconnectAttempt: state.reconnectAttempt)),
                const SizedBox(width: 12),
                Expanded(child: _ConfidenceBar(value: status == DisplayStatus.idle ? 0 : state.track.confidence)),
                const SizedBox(width: 8),
                _LockButton(lock: state.lock, quran: quran, onLock: onLock, onUnlock: onUnlock),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Position extends StatelessWidget {
  const _Position(this.position, this.quran, this.state);

  final Position position;
  final Quran quran;
  final ListenState state;

  @override
  Widget build(BuildContext context) {
    final surah = quran.surah(position.surah);
    final upcoming = state.track.upcoming == position;
    return Semantics(
      label: 'Surah ${surah.nameTranslit}, ayah ${position.ayah}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The Arabic name scales down rather than wrapping or overflowing,
          // whatever the surah or the user's font-size setting.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              surah.nameAr,
              textDirection: TextDirection.rtl,
              maxLines: 1,
              style: TextStyle(fontFamily: quranFont, fontSize: 38, height: 1.3, color: context.scheme.onSurface),
            ),
          ),
          Text(
            surah.nameTranslit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            'Ayah ${position.ayah} of ${surah.ayahCount} · Juz ${quran.juzOf(position.verseId)}'
            '${upcoming ? ' · next' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(color: context.colors.muted),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.state, required this.status, required this.quran});

  final ListenState state;
  final DisplayStatus status;
  final Quran quran;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (status) {
      DisplayStatus.connecting => ('Connecting…', 'The first time, the server loads its speech model.'),
      DisplayStatus.searching => ('Listening…', 'Finding the surah. This takes a few words.'),
      DisplayStatus.paused => ('Paused', 'Listening stops when the app is in the background.'),
      DisplayStatus.reconnecting => ('Reconnecting…', 'The microphone keeps listening meanwhile.'),
      _ => ('Ready to follow', 'Tap the microphone when the imam begins.'),
    };
    // A first guess is useful but never shown as fact.
    final pending = state.track.pending;
    final guess = pending == null ? null : 'Maybe ${quran.surah(pending.surah).nameTranslit} ${pending.ref}…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          guess ?? subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodyMedium?.copyWith(color: context.colors.muted),
        ),
      ],
    );
  }
}

/// Lock recognition to the surah on screen, or show that it is locked.
class _LockButton extends StatelessWidget {
  const _LockButton({required this.lock, required this.quran, this.onLock, this.onUnlock});

  final Hint? lock;
  final Quran quran;
  final VoidCallback? onLock;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final locked = lock;
    if (locked == null) {
      return IconButton(
        tooltip: 'Stay on this surah',
        visualDensity: VisualDensity.compact,
        onPressed: onLock,
        icon: const Icon(Icons.lock_open_rounded, size: 20),
      );
    }
    final label = switch (locked) {
      SurahHint(:final surah) => quran.surah(surah).nameTranslit,
      JuzHint(:final juz) => 'Juz $juz',
    };
    return Tooltip(
      message: 'Locked to $label. Tap to unlock.',
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(Icons.lock_rounded, size: 16, color: context.scheme.primary),
        label: Text(label, overflow: TextOverflow.ellipsis),
        onPressed: onUnlock,
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.reconnectAttempt = 0});

  final DisplayStatus status;
  final int reconnectAttempt;

  @override
  Widget build(BuildContext context) {
    final color = status.color(context);
    final label = status == DisplayStatus.reconnecting && reconnectAttempt > 1
        ? '${status.label} ($reconnectAttempt)'
        : status.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  const _ConfidenceBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Confidence ${(value * 100).round()} percent',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value),
          duration: const Duration(milliseconds: 300),
          builder: (context, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: 5,
            backgroundColor: context.scheme.onSurface.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation(context.scheme.primary),
          ),
        ),
      ),
    );
  }
}
