import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../display_status.dart';

/// The single primary action: start or stop following. A full-width pill
/// with a label, not an icon; it sits at the bottom, away from the Quran
/// column, so a hand resting on a lap does not end the session.
///
/// Ready: filled `ink` (64px on the ready screen, 56px otherwise). Active:
/// outlined `ink`. Preparing and stopping: outlined, disabled. After an error
/// it returns to Ready; the Notice above explains and offers the fix.
class ListenControl extends StatelessWidget {
  const ListenControl({super.key, required this.status, required this.onPressed});

  final DisplayStatus status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = status.active;
    final busy = status == DisplayStatus.connecting || status == DisplayStatus.stopping;
    final height = status == DisplayStatus.ready ? RubricSpace.s16 : 56.0;
    final label = switch (status) {
      DisplayStatus.connecting => 'Preparing…',
      DisplayStatus.stopping => 'Finishing the last words…',
      _ when active => 'Stop following',
      _ => 'Start following',
    };
    final focusSide = MaterialStateProperty.resolveWith<BorderSide?>((s) {
      if (s.contains(MaterialState.focused)) return BorderSide(color: c.signal, width: 2);
      if (s.contains(MaterialState.disabled)) return BorderSide(color: c.hairline);
      return active ? BorderSide(color: c.ink) : null;
    });
    final size = MaterialStatePropertyAll(Size.fromHeight(height));
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);

    return Semantics(
      button: true,
      enabled: !busy,
      label: active ? 'Stop following' : 'Start following the imam',
      excludeSemantics: true,
      onTap: busy ? null : onPressed,
      child: AnimatedContainer(
        duration: RubricMotion.quick,
        curve: RubricMotion.standard,
        height: height,
        child: active
            ? OutlinedButton(
                onPressed: busy ? null : onPressed,
                style: ButtonStyle(
                  side: focusSide,
                  minimumSize: size,
                  textStyle: MaterialStatePropertyAll(RubricText.labelLg),
                ),
                child: text,
              )
            : FilledButton(
                onPressed: onPressed,
                style: ButtonStyle(side: focusSide, minimumSize: size),
                child: text,
              ),
      ),
    );
  }
}

/// Five 3px bars from the app's microphone peak level, and what that level
/// means in words. Deliberately neutral (`level-on` / `level-off`): the
/// microphone is never cinnabar. Updated at most every 80ms by the
/// controller; nothing else about it moves.
class MicLevel extends StatelessWidget {
  const MicLevel({super.key, required this.level, required this.hearing});

  /// Peak level, 0..1.
  final double level;

  /// Sound at or above the quiet threshold was picked up just now. About
  /// loudness only: it never claims the audio is clear.
  final bool hearing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Peaks are small at prayer-row distance: a square root spreads them out.
    final lit = hearing ? (5 * math.sqrt(level.clamp(0.0, 1.0))).ceil().clamp(1, 5) : 0;
    return Semantics(
      label: hearing ? 'Hearing sound' : 'Very little sound',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 5; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Container(width: 3, height: 6.0 + 2 * i, color: i < lit ? c.levelOn : c.levelOff),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              hearing ? 'Hearing sound' : 'Very little sound',
              style: RubricText.caption.copyWith(color: c.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
