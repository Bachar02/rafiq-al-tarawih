import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/recognition/models.dart';
import '../../../data/quran.dart';
import 'mushaf_view.dart';

enum AyahAction { imamIsHere, lockSurah, unlock }

/// Tapping an ayah: tell the app where the imam really is.
Future<AyahAction?> showAyahActions(
  BuildContext context, {
  required Verse verse,
  required Quran quran,
  required bool listening,
  required Hint? lock,
}) {
  final surah = quran.surah(verse.surah);
  final lockedHere = lock is SurahHint && lock.surah == verse.surah;
  return showModalBottomSheet<AyahAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      // Scrolls rather than overflowing with large system fonts.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${surah.nameTranslit} · ayah ${verse.ayah}',
              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '${verse.uthmani} ۝${arabicDigits(verse.ayah)}',
              textDirection: TextDirection.rtl,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: quranFont, fontSize: 20, height: 1.9),
            ),
            const SizedBox(height: 12),
            ListTile(
              enabled: listening,
              leading: const Icon(Icons.my_location),
              title: const Text('The imam is here'),
              subtitle: Text(listening
                  ? 'Jump to this ayah and keep following from it'
                  : 'Start listening first, then tap the ayah the imam is on'),
              onTap: () => Navigator.pop(context, AyahAction.imamIsHere),
            ),
            if (lockedHere)
              ListTile(
                leading: const Icon(Icons.lock_open),
                title: const Text('Unlock'),
                subtitle: const Text('Let the app search the whole Quran again'),
                onTap: () => Navigator.pop(context, AyahAction.unlock),
              )
            else
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text('Stay on ${surah.nameTranslit}'),
                subtitle: const Text('The app will not look in other surahs (al-Fatiha still allowed)'),
                onTap: () => Navigator.pop(context, AyahAction.lockSurah),
              ),
          ],
        ),
      ),
    ),
  );
}
