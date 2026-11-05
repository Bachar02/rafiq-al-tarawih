import 'package:flutter/material.dart';

import '../theme.dart';

/// Rubric bottom sheet: `surface-raised` over a darkening scrim, top corners
/// `radius-sheet`, grab handle in `hairline` (all from the theme), and at most
/// 70% of the screen tall so the current ayah stays visible above it.
/// Dismissed by drag, scrim tap or the system back gesture.
Future<T?> showRubricSheet<T>(BuildContext context, {required WidgetBuilder builder, bool expand = false}) {
  final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(maxHeight: maxHeight),
    builder: (context) => expand ? SizedBox(height: maxHeight, child: builder(context)) : builder(context),
  );
}

/// Sheet title (`ui` 20/28, 500) and its one-line explanation (`caption`).
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.explanation});

  final String title;
  final String? explanation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(title, style: RubricText.sheetTitle.copyWith(color: c.ink))),
        if (explanation != null) ...[
          const SizedBox(height: RubricSpace.s1),
          Text(explanation!, style: RubricText.caption.copyWith(color: c.inkSecondary)),
        ],
      ],
    );
  }
}
