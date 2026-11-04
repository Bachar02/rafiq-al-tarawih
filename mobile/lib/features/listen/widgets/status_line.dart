import 'package:flutter/material.dart';

import '../../../app/components/position_marker.dart';
import '../../../app/theme.dart';
import '../display_status.dart';
import '../../../l10n/l10n.dart';

/// One line that says what Rafiq knows right now, with an optional caption:
/// the only place recognition state is put into words.
///
/// Never says "can't hear" or "poor audio": the engine has no audio-quality
/// measurement. The marker slot is always reserved, so the line never moves;
/// text swaps crossfade in [RubricMotion.quick]. Screen readers hear state
/// changes politely, not ayah-to-ayah progress.
class StatusLine extends StatelessWidget {
  const StatusLine({
    super.key,
    required this.status,
    required this.held,
    this.ayah,
    this.reconnectAttempt = 0,
    this.note,
  });

  final DisplayStatus status;

  /// A position is on screen.
  final bool held;

  /// The ayah on screen, cited in the inferred-state captions.
  final int? ayah;
  final int reconnectAttempt;

  /// An extra line under the caption (e.g. repeated-text alternatives).
  final String? note;

  static const _markerSize = 14.0;
  static const _indent = _markerSize + RubricSpace.s2;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final marker = status.marker(held: held);
    final l = context.l10n;
    var label = status.label(l);
    if (status == DisplayStatus.reconnecting && reconnectAttempt > 1) label = '$label ($reconnectAttempt)';
    final caption = status.caption(l, ayah);
    final captionStyle = RubricText.caption.copyWith(color: c.inkSecondary);

    return AnimatedSize(
      duration: RubricMotion.quick,
      curve: RubricMotion.standard,
      alignment: AlignmentDirectional.topStart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 24,
            child: Row(
              children: [
                SizedBox.square(
                  dimension: _markerSize,
                  child: marker == MarkerFill.none ? null : PositionMarker(filled: marker == MarkerFill.filled),
                ),
                const SizedBox(width: RubricSpace.s2),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: AnimatedSwitcher(
                      duration: RubricMotion.quick,
                      layoutBuilder: (current, previous) => Stack(
                          alignment: AlignmentDirectional.centerStart,
                          children: [...previous, if (current != null) current]),
                      child: Text(
                        label,
                        key: ValueKey(label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RubricText.labelLg.copyWith(color: c.ink),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (caption != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: _indent, top: 2),
              child: Text(caption, style: captionStyle),
            ),
          if (note != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: _indent, top: 2),
              child: Text(note!, style: captionStyle),
            ),
        ],
      ),
    );
  }
}
