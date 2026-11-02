import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../display_status.dart';

/// The one control: start or stop following. The ring breathes with the
/// microphone level, so the user can see that the phone hears the imam.
class MicButton extends StatelessWidget {
  const MicButton({super.key, required this.status, required this.level, required this.onPressed});

  final DisplayStatus status;

  /// Microphone level, 0..1.
  final double level;
  final VoidCallback? onPressed;

  static const _size = 76.0;

  bool get _active => switch (status) {
        DisplayStatus.connecting ||
        DisplayStatus.searching ||
        DisplayStatus.following ||
        DisplayStatus.uncertain ||
        DisplayStatus.lost ||
        DisplayStatus.reconnecting ||
        DisplayStatus.stopping =>
          true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final busy = status == DisplayStatus.connecting || status == DisplayStatus.stopping;
    final color = _active ? context.colors.lost : context.scheme.primary;
    final ring = _active ? _size + 10 + 36 * level.clamp(0, 1) : _size;
    return Semantics(
      button: true,
      label: _active ? 'Stop following' : 'Start following the imam',
      child: SizedBox(
        width: _size + 50,
        height: _size + 50,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: ring,
              height: ring,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.18)),
            ),
            SizedBox(
              width: _size,
              height: _size,
              child: ElevatedButton(
                onPressed: busy ? null : onPressed,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  backgroundColor: color,
                  foregroundColor: context.scheme.onPrimary,
                  disabledBackgroundColor: color.withOpacity(0.6),
                  elevation: 2,
                ),
                child: busy
                    ? SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 3, color: context.scheme.onPrimary),
                      )
                    : Icon(_active ? Icons.stop_rounded : Icons.mic_rounded, size: 36),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
