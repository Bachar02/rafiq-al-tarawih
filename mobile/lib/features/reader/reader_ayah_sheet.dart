import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/components/quran_text.dart';
import '../../app/components/sheet.dart';
import '../../app/theme.dart';
import '../../core/text/quran_display.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';
import '../../l10n/l10n.dart';

enum ReaderAyahAction { bookmark, removeBookmark, note, share, copy }

/// The reader's actions on one ayah (a tap on its text).
Future<ReaderAyahAction?> showReaderAyahSheet(
  BuildContext context, {
  required Verse verse,
  required SurahNames names,
  required bool bookmarked,
  required bool noted,
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
            SheetHeader(title: context.l10n.ayahSheetTitle(names.of(verse.surah), verse.ayah)),
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
                label: Text(context.l10n.removeBookmark),
              )
            else
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, ReaderAyahAction.bookmark),
                icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                label: Text(context.l10n.bookmark),
              ),
            const SizedBox(height: RubricSpace.s2),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, ReaderAyahAction.note),
              icon: Icon(noted ? Icons.edit_note : Icons.note_add_outlined, size: 20),
              label: Text(noted ? context.l10n.editNote : context.l10n.addNote),
            ),
            const SizedBox(height: RubricSpace.s2),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, ReaderAyahAction.share),
              icon: const Icon(Icons.ios_share, size: 20),
              label: Text(context.l10n.share),
            ),
            const SizedBox(height: RubricSpace.s2),
            TextButton.icon(
              onPressed: () => Navigator.pop(context, ReaderAyahAction.copy),
              icon: const Icon(Icons.copy_outlined, size: 20),
              label: Text(context.l10n.copyAyah),
            ),
            const SizedBox(height: RubricSpace.s2),
            const _ComingSoon(),
          ],
        ),
      ),
    );

/// The text put on the clipboard: the ayah as printed, then its reference.
String ayahClipboardText(Verse verse, SurahNames names) =>
    '${verse.uthmani} ${ayahEndMarker(verse.ayah)}\n— ${names.of(verse.surah)} ${verse.surah}:${verse.ayah}';

Future<void> copyAyah(Verse verse, SurahNames names) =>
    Clipboard.setData(ClipboardData(text: ayahClipboardText(verse, names)));

/// Listen, translation and tafsir will live here: shown, visibly not yet
/// working, so the sheet does not change shape when they arrive.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: c.hairline),
        Row(
          children: [
            for (final (icon, label) in [
              (Icons.play_arrow_outlined, l.listen),
              (Icons.translate, l.translation),
              (Icons.menu_book_outlined, l.tafsir),
            ])
              Expanded(
                // Icon over label, so three fit side by side in any language.
                child: TextButton(
                  onPressed: null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20),
                      const SizedBox(height: RubricSpace.s1),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RubricText.caption,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Text(
          l.comingSoon,
          textAlign: TextAlign.center,
          style: RubricText.caption.copyWith(color: c.inkSecondary),
        ),
      ],
    );
  }
}
