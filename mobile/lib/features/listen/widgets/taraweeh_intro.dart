import 'package:flutter/material.dart';

import '../../../app/components/sheet.dart';
import '../../../app/theme.dart';

/// The first time Taraweeh mode opens (and never again): what it does, what
/// it needs, and what it does not claim. Returns true to start following.
Future<bool?> showTaraweehIntro(BuildContext context) => showRubricSheet<bool>(
      context,
      builder: (context) {
        final c = context.colors;
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
              const SheetHeader(
                title: 'Taraweeh mode',
                explanation: 'Rafiq listens to the imam and shows the ayah being recited, live.',
              ),
              const SizedBox(height: RubricSpace.s4),
              point(Icons.mic_none, 'It uses the microphone only while following. The screen stays on.'),
              point(Icons.wifi_outlined,
                  'This test build recognises on a computer on the same Wi-Fi (Settings → Recognition server).'),
              point(Icons.menu_book_outlined, 'It follows recitation in Ḥafṣ ʿan ʿĀṣim only.'),
              point(Icons.back_hand_outlined,
                  'If it is ever wrong, tap the ayah the imam is on. When unsure, it says so rather than guess.'),
              const SizedBox(height: RubricSpace.s2),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Start following')),
              const SizedBox(height: RubricSpace.s2),
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
            ],
          ),
        );
      },
    );
