import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/components/quran_text.dart';
import '../../app/components/sheet.dart';
import '../../app/theme.dart';
import '../../core/text/quran_display.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';

enum ReaderAyahAction { bookmark, removeBookmark, copy }

/// The reader's actions on one ayah (a tap on its text).
Future<ReaderAyahAction?> showReaderAyahSheet(
  BuildContext context, {
  required Verse verse,
  required SurahNames names,
  required bool bookmarked,
}) =>
    showRubricSheet<ReaderAyahAction>(
      context,
      builder: (context) => SingleChildScrollView(
        // Scrolls rather than overflowing with large system fonts.
        padding: const EdgeInsets.fromLTRB(RubricSpace.s6, 0, RubricSpace.s6, RubricSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(title: '${names.of(verse.surah)} · ayah ${verse.ayah}'),
            const SizedBox(height: RubricSpace.s2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: AyahBlock(verse: verse, tone: AyahTone.reading, fontSize: 22, justify: false),
              ),
            ),
            const SizedBox(height: RubricSpace.s4),
            if (bookmarked)
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, ReaderAyahAction.removeBookmark),
                icon: const Icon(Icons.bookmark_remove_outlined, size: 20),
                label: const Text('Remove bookmark'),
              )
            else
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, ReaderAyahAction.bookmark),
                icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                label: const Text('Bookmark'),
              ),
            const SizedBox(height: RubricSpace.s2),
            TextButton.icon(
              onPressed: () => Navigator.pop(context, ReaderAyahAction.copy),
              icon: const Icon(Icons.copy_outlined, size: 20),
              label: const Text('Copy the ayah'),
            ),
          ],
        ),
      ),
    );

/// The text put on the clipboard: the ayah as printed, then its reference.
String ayahClipboardText(Verse verse, SurahNames names) =>
    '${verse.uthmani} ${ayahEndMarker(verse.ayah)}\n— ${names.of(verse.surah)} ${verse.surah}:${verse.ayah}';

Future<void> copyAyah(Verse verse, SurahNames names) =>
    Clipboard.setData(ClipboardData(text: ayahClipboardText(verse, names)));
