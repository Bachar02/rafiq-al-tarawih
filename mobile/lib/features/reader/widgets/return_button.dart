import 'package:flutter/material.dart';

import '../../../app/navigation.dart';
import '../../../app/theme.dart';
import '../../../l10n/l10n.dart';

/// The reader's way back after a jump from elsewhere ("Back to notes"): a
/// floating pill at the foot of the text, styled like "Back to the imam".
/// The phone's back button does the same.
class ReaderReturnButton extends StatelessWidget {
  const ReaderReturnButton({super.key, required this.to, required this.onTap});

  final ReaderOrigin to;
  final VoidCallback onTap;

  static String label(AppLocalizations l, ReaderOrigin to) => switch (to) {
        TabOrigin(view: BookmarksView.notes) => l.backToNotes,
        TabOrigin(tab: HomeTab.surahs) => l.backToSurahs,
        TabOrigin() => l.backToBookmarks,
        KhatmOrigin() => l.backToKhatm,
        SearchOrigin() => l.backToSearch,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = label(context.l10n, to);
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      onTap: onTap,
      child: OutlinedButton(
        onPressed: onTap,
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(c.surfaceRaised),
          foregroundColor: WidgetStatePropertyAll(c.ink),
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: RubricSpace.s4)),
          textStyle: WidgetStatePropertyAll(RubricText.label),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(color: s.contains(WidgetState.pressed) ? c.ink : c.hairline),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Points the way back in either reading direction.
            const BackButtonIcon(),
            const SizedBox(width: RubricSpace.s2),
            Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
