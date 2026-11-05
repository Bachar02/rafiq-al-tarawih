import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme.dart';

/// A page number that is on or off (read, or counted): ink-filled when on,
/// outlined when off, every one the same width so a run of pages lines up.
/// Screen readers hear "Page 42, selected".
class PageToggle extends StatelessWidget {
  const PageToggle({super.key, required this.page, required this.on, required this.onChanged});

  final int page;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: context.l10n.pageNumber(page),
      selected: on,
      button: true,
      excludeSemantics: true,
      onTap: () => onChanged(!on),
      child: FilterChip(
        showCheckmark: false,
        selected: on,
        onSelected: onChanged,
        selectedColor: c.ink,
        backgroundColor: c.surface,
        side: BorderSide(color: on ? c.ink : c.hairline),
        label: SizedBox(
          width: 36,
          child: Text(
            '$page',
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: RubricText.label.copyWith(color: on ? c.ground : c.ink),
          ),
        ),
      ),
    );
  }
}
