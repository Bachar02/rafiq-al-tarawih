import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/components/quran_text.dart';
import '../../../app/components/sheet.dart';
import '../../../app/theme.dart';
import '../../../core/recognition/models.dart';
import '../../../data/quran.dart';
import '../../../data/surah_names.dart';

enum AyahAction { imamIsHere, lockSurah, unlock }

/// Tapping an ayah: tell the app where the imam really is. A deliberate
/// two-step action (tap, then confirm), never a single tap; one light haptic
/// tap confirms the correction.
Future<AyahAction?> showAyahActions(
  BuildContext context, {
  required Verse verse,
  required Quran quran,
  required SurahNames names,
  required bool listening,
  required Hint? lock,
}) {
  final lockedHere = lock is SurahHint && lock.surah == verse.surah;
  final name = names.of(verse.surah);
  return showRubricSheet<AyahAction>(
    context,
    builder: (context) {
      final c = context.colors;
      return SingleChildScrollView(
        // Scrolls rather than overflowing with large system fonts.
        padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: '$name · ayah ${verse.ayah}',
              explanation: listening
                  ? 'Rafiq jumps to this ayah and keeps following from it.'
                  : 'Start following first, then tap the ayah the imam is on.',
            ),
            const SizedBox(height: RubricSpace.s2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: AyahBlock(verse: verse, tone: AyahTone.upcoming, fontSize: 22, justify: false),
              ),
            ),
            const SizedBox(height: RubricSpace.s4),
            FilledButton(
              onPressed: listening
                  ? () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context, AyahAction.imamIsHere);
                    }
                  : null,
              style: FilledButton.styleFrom(
                disabledBackgroundColor: Colors.transparent,
                side: listening ? null : BorderSide(color: c.hairline),
              ),
              child: const Text('The imam is here'),
            ),
            const SizedBox(height: RubricSpace.s2),
            if (lockedHere)
              TextButton(
                onPressed: () => Navigator.pop(context, AyahAction.unlock),
                child: const Text('Unlock: search the whole Quran again'),
              )
            else
              TextButton(
                onPressed: () => Navigator.pop(context, AyahAction.lockSurah),
                child: Text('Stay on $name'),
              ),
          ],
        ),
      );
    },
  );
}

/// "Stay on this surah": recognition will not look in other surahs until
/// unlocked. Al-Fatiha is still recognised at each rakʿah: that is what the
/// engine's lock does. Returns true to lock.
Future<bool?> showLockSheet(BuildContext context, {required String surahName}) => showRubricSheet<bool>(
      context,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: 'Stay on $surahName',
              explanation: 'Rafiq will not look in other surahs until you unlock. '
                  'Al-Fatiha is still recognised at each rakʿah.',
            ),
            const SizedBox(height: RubricSpace.s6),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stay on this surah')),
          ],
        ),
      ),
    );
