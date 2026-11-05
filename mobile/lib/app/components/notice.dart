import 'package:flutter/material.dart';

import '../theme.dart';
import '../../l10n/l10n.dart';

/// A calm block that explains a stopped or blocked session and offers the one
/// action that fixes it. The only component that uses `signal` (lapis):
/// never cinnabar, never red — errors are not alarming during prayer; the
/// icon shape and the words carry the meaning.
///
/// Placed directly above the listen control, never over the Quran column.
/// Without an action it is a transient notice (engine warnings).
class Notice extends StatelessWidget {
  const Notice({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.alert = false,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  /// An error (announced assertively) rather than a status.
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      // Flutter has one live-region politeness; errors also get a hint.
      hint: alert ? context.l10n.needsYourAction : null,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.hairline),
          borderRadius: BorderRadius.circular(RubricRadius.md),
        ),
        padding: EdgeInsetsDirectional.fromSTEB(
          RubricSpace.s4,
          RubricSpace.s4,
          onDismiss == null ? RubricSpace.s4 : RubricSpace.s1,
          onAction == null ? RubricSpace.s4 : RubricSpace.s1,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 22, color: c.signal)),
            const SizedBox(width: RubricSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: RubricText.label.weighted(500).copyWith(color: c.ink)),
                  if (body != null && body!.isNotEmpty)
                    Text(body!, style: RubricText.caption.copyWith(color: c.inkSecondary)),
                  if (actionLabel != null && onAction != null)
                    TextButton(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: c.signal,
                        padding: EdgeInsets.zero,
                        alignment: AlignmentDirectional.centerStart,
                        textStyle: RubricText.label.weighted(500),
                      ),
                      child: Text(actionLabel!),
                    ),
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                tooltip: context.l10n.dismiss,
                icon: const Icon(Icons.close, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}
