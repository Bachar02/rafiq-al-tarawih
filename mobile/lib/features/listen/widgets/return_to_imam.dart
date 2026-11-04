import 'package:flutter/material.dart';

import '../../../app/components/position_marker.dart';
import '../../../app/theme.dart';
import '../../../core/recognition/models.dart';

/// A floating pill that brings the reader back to the imam's live position
/// after the user scrolls or browses away. It carries the position marker
/// because it points at the position.
///
/// The reference ("· 93:4") comes only from a confirmed position; when the
/// position is not sure the marker is hollow and the reference is omitted.
/// No disabled state: with no position, it is not shown.
class ReturnToImam extends StatelessWidget {
  const ReturnToImam(
      {super.key, required this.visible, required this.position, required this.sure, required this.onTap});

  final bool visible;
  final Position? position;
  final bool sure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (position == null) return const SizedBox.shrink();
    final label = sure ? 'Back to the imam · ${position!.ref}' : 'Back to the imam';
    // Stays built while hidden so it can fade out; invisible to taps and
    // screen readers meanwhile.
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: RubricMotion.quick,
          curve: visible ? RubricMotion.standard : RubricMotion.exit,
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            onTap: onTap,
            child: OutlinedButton(
              onPressed: onTap,
              style: ButtonStyle(
                backgroundColor: MaterialStatePropertyAll(c.surfaceRaised),
                foregroundColor: MaterialStatePropertyAll(c.ink),
                minimumSize: const MaterialStatePropertyAll(Size(0, 56)),
                padding: const MaterialStatePropertyAll(EdgeInsets.symmetric(horizontal: RubricSpace.s6)),
                textStyle: MaterialStatePropertyAll(RubricText.labelLg),
                side: MaterialStateProperty.resolveWith(
                  (s) => BorderSide(color: s.contains(MaterialState.pressed) ? c.ink : c.hairline),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PositionMarker(filled: sure),
                  const SizedBox(width: RubricSpace.s3),
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
