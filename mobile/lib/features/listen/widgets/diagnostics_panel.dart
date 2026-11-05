import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../listen_state.dart';

/// Live transcript for field testing (Settings → Developer → Show diagnostics).
class TranscriptPanel extends StatelessWidget {
  const TranscriptPanel({super.key, required this.state});

  final ListenState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = [if (state.livePartial != null) state.livePartial!, ...state.transcript.reversed.take(8)];
    final muted = RubricText.caption.copyWith(color: c.inkSecondary);
    final tabular = muted.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(RubricRadius.md),
      ),
      padding: const EdgeInsets.all(RubricSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'DIAGNOSTICS · ${state.device ?? 'model not loaded'}'
            '${state.detectedAfter != null ? ' · detected after ${(state.detectedAfter!.inMilliseconds / 1000).toStringAsFixed(1)} s' : ''}',
            style: RubricText.overline.copyWith(color: c.inkSecondary),
          ),
          const SizedBox(height: RubricSpace.s1),
          if (lines.isEmpty) Text('Nothing heard yet', style: muted),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(width: 54, child: Text(l.shown?.ref ?? '—', style: tabular.copyWith(color: c.ink))),
                  Expanded(
                    child: Text(
                      l.isFinal ? l.text : '${l.text} …',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: quranFont,
                        fontSize: 16,
                        height: 1.8,
                        color: l.isFinal ? c.ink : c.inkSecondary,
                      ),
                    ),
                  ),
                  SizedBox(width: 56, child: Text('${l.asrMs} ms', style: tabular, textAlign: TextAlign.end)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
