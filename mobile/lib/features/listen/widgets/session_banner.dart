import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../listen_state.dart';

/// Errors that need the user, with the action that fixes them.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({
    super.key,
    required this.error,
    required this.message,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onDismiss,
  });

  final ListenError error;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (icon, title, help) = switch (error) {
      ListenError.micPermission => (
          Icons.mic_off_rounded,
          'Microphone access needed',
          'If you denied it before, allow it in your phone settings: Apps → Rafiq → Permissions → Microphone.',
        ),
      ListenError.unreachable => (
          Icons.wifi_off_rounded,
          'Cannot reach the server',
          'Check that the Rafiq server is running on your laptop, that the phone is on the same Wi-Fi, '
              'and that the address in settings is right.',
        ),
      ListenError.server => (Icons.error_outline_rounded, 'The server had a problem', null),
      ListenError.microphone => (Icons.mic_off_rounded, 'Microphone problem', null),
    };
    return Card(
      color: context.colors.lost.withOpacity(0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: context.colors.lost),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(message, style: context.text.bodySmall),
                      if (help != null) ...[
                        const SizedBox(height: 4),
                        Text(help, style: context.text.bodySmall?.copyWith(color: context.colors.muted)),
                      ],
                    ],
                  ),
                ),
                IconButton(onPressed: onDismiss, icon: const Icon(Icons.close, size: 18), tooltip: 'Dismiss'),
              ],
            ),
            // Wrap, not Row: with large system fonts the buttons stack instead of overflowing.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (error == ListenError.unreachable)
                  TextButton(onPressed: onOpenSettings, child: const Text('Server settings')),
                FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Live transcript for field testing (Settings → Show diagnostics).
class TranscriptPanel extends StatelessWidget {
  const TranscriptPanel({super.key, required this.state});

  final ListenState state;

  @override
  Widget build(BuildContext context) {
    final lines = [if (state.livePartial != null) state.livePartial!, ...state.transcript.reversed.take(8)];
    final muted = context.text.labelSmall?.copyWith(color: context.colors.muted);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Diagnostics · ${state.device ?? 'model not loaded'}'
              '${state.detectedAfter != null ? ' · detected after ${(state.detectedAfter!.inMilliseconds / 1000).toStringAsFixed(1)} s' : ''}',
              style: muted,
            ),
            const SizedBox(height: 6),
            if (lines.isEmpty) Text('Nothing heard yet', style: muted),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(width: 54, child: Text(l.shown?.ref ?? '—', style: context.text.labelMedium)),
                    Expanded(
                      child: Text(
                        l.isFinal ? l.text : '${l.text} …',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontFamily: quranFont,
                          fontSize: 16,
                          fontStyle: l.isFinal ? FontStyle.normal : FontStyle.italic,
                          color: l.isFinal ? null : context.colors.muted,
                        ),
                      ),
                    ),
                    SizedBox(width: 52, child: Text('${l.asrMs} ms', style: muted, textAlign: TextAlign.end)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
