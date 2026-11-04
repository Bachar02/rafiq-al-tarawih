import 'package:flutter/material.dart';

import '../../core/text/quran_display.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';
import '../theme.dart';

/// "Al-Baqarah 2:255": a verse's reference as the app writes it.
String verseReference(Verse verse, SurahNames names) => '${names.of(verse.surah)} ${verse.surah}:${verse.ayah}';

/// "Juz 3 · Page 42": where a verse falls.
String verseLocation(Quran quran, int verseId) => 'Juz ${quran.juzOf(verseId)} · Page ${quran.pageOf(verseId)}';

/// A place in the Quran in a list: a title, a quiet line, and optionally the
/// opening of the ayah in the Quran's own script.
class PlaceTile extends StatelessWidget {
  const PlaceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.verse,
    this.leading,
    this.trailing,
    this.selected = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Shown as two lines of Quran text under the title.
  final Verse? verse;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      selected: selected,
      onTap: onTap,
      leading: leading,
      trailing: trailing,
      contentPadding: const EdgeInsetsDirectional.only(start: RubricSpace.s4, end: RubricSpace.s2),
      // One line each, so rows of a kind have one height (long lists size
      // every row from one measured prototype).
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: selected ? RubricText.label.weighted(500) : null,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (verse != null)
            Padding(
              padding: const EdgeInsets.only(top: RubricSpace.s1),
              child: Text(
                preparePauseMarks(verse!.uthmani),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.start,
                textScaler: TextScaler.noScaling,
                style: RubricText.quranBody.copyWith(fontSize: 19, height: 1.9, color: c.inkUpcoming),
              ),
            ),
        ],
      ),
    );
  }
}
