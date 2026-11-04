import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../l10n/l10n.dart';

/// The way into Taraweeh mode, floating over the reader. It steps aside
/// while the user scrolls down through the text and returns when they
/// scroll back or stop.
class TaraweehEntry extends StatelessWidget {
  const TaraweehEntry({super.key, required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  static const height = 52.0;

  @override
  Widget build(BuildContext context) {
    final reduced = RubricMotion.reduced(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible || reduced ? Offset.zero : const Offset(0, 1.6),
        duration: RubricMotion.sheet,
        curve: visible ? RubricMotion.standard : RubricMotion.exit,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: RubricMotion.quick,
          child: Semantics(
            button: true,
            label: context.l10n.semTaraweehEntry,
            excludeSemantics: true,
            onTap: onPressed,
            child: FilledButton.icon(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, height),
                padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s6),
              ),
              icon: const Icon(Icons.mic_none, size: 20),
              label: Text(context.l10n.taraweeh),
            ),
          ),
        ),
      ),
    );
  }
}
