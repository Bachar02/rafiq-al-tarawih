import 'package:flutter/material.dart';

import '../theme.dart';
import 'settings_group.dart';
import 'sheet.dart';

/// A sheet of options, the current one checked. Returns the one tapped, or
/// null if the sheet is dismissed.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  String? explanation,
  required List<T> options,
  required T current,
  required String Function(T) label,
  String? Function(T)? detail,
}) =>
    showRubricSheet<T>(
      context,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeader(title: title, explanation: explanation),
            const SizedBox(height: RubricSpace.s4),
            RubricGroup(
              children: [
                for (final option in options)
                  RubricRow(
                    label: label(option),
                    detail: detail?.call(option),
                    selected: option == current,
                    trailing: option == current ? Icon(Icons.check, color: context.colors.ink, size: 20) : null,
                    onTap: () => Navigator.pop(context, option),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
