import 'package:flutter/material.dart';

import '../theme.dart';

/// Grouped rows: `surface` fill, `radius-md`, rows divided by `hairline`, an
/// optional group label above. Used by settings and by list sheets.
class RubricGroup extends StatelessWidget {
  const RubricGroup({super.key, this.label, required this.children});

  /// Shown above the group: overline in Latin (uppercase, tracked).
  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(top: RubricSpace.s6, bottom: RubricSpace.s2),
            child: Semantics(
              header: true,
              child: Text(label!.toUpperCase(), style: RubricText.overline.copyWith(color: c.inkSecondary)),
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(RubricRadius.md),
          child: Material(
            color: c.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, child) in children.indexed) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: c.hairline),
                  child,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One settings row: 52px minimum, label in `ink`, value in `ink-secondary`.
/// Pressed: `surface-raised`. Disabled: label in `ink-secondary`, no tap.
/// Mirrors fully in right-to-left layouts.
class RubricRow extends StatelessWidget {
  const RubricRow({
    super.key,
    required this.label,
    this.detail,
    this.value,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.selected = false,
  });

  final String label;

  /// A caption under the label.
  final String? detail;

  /// The current value, at the end of the row.
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  /// A chosen option in a list (label in weight 500).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labelStyle = RubricText.label.copyWith(color: enabled ? c.ink : c.inkSecondary);
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: enabled ? onTap : null,
        highlightColor: c.surfaceRaised,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s4, vertical: RubricSpace.s2),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: selected ? labelStyle.weighted(500) : labelStyle),
                      if (detail != null) Text(detail!, style: RubricText.caption.copyWith(color: c.inkSecondary)),
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: RubricSpace.s3),
                  // Tight, so the value sits at the row's trailing edge.
                  Expanded(
                    flex: 2,
                    child: Text(
                      value!,
                      textAlign: TextAlign.end,
                      style: RubricText.label.copyWith(color: c.inkSecondary),
                    ),
                  ),
                ],
                if (trailing != null) ...[const SizedBox(width: RubricSpace.s3), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
