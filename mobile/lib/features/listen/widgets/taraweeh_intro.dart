import 'package:flutter/material.dart';

import '../../../app/components/sheet.dart';
import '../../../app/theme.dart';
import '../../../l10n/l10n.dart';

/// The first time Taraweeh mode opens (and never again): what it does, what
/// it needs, and what it does not claim. Returns true to start following.
Future<bool?> showTaraweehIntro(BuildContext context) => showRubricSheet<bool>(
      context,
      builder: (context) {
        final c = context.colors;
        final l = context.l10n;
        Widget point(IconData icon, String text) => Padding(
              padding: const EdgeInsets.only(bottom: RubricSpace.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: c.inkSecondary),
                  const SizedBox(width: RubricSpace.s3),
                  Expanded(child: Text(text, style: RubricText.label.copyWith(color: c.ink))),
                ],
              ),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(title: l.introTitle, explanation: l.introLead),
              const SizedBox(height: RubricSpace.s4),
              point(Icons.mic_none, l.introMic),
              point(Icons.wifi_outlined, l.introServer),
              point(Icons.menu_book_outlined, l.introHafs),
              point(Icons.back_hand_outlined, l.introCorrect),
              const SizedBox(height: RubricSpace.s2),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.controlStart)),
              const SizedBox(height: RubricSpace.s2),
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.notNow)),
            ],
          ),
        );
      },
    );
