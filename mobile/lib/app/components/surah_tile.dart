import 'package:flutter/material.dart';

import '../../data/quran.dart';
import '../../data/surah_names.dart';
import '../theme.dart';
import '../../l10n/l10n.dart';

/// A surah in a list: number, display name, ayah count, Arabic name.
class SurahTile extends StatelessWidget {
  const SurahTile({super.key, required this.surah, required this.names, required this.onTap, this.selected = false});

  final Surah surah;
  final SurahNames names;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListTile(
      selected: selected,
      contentPadding: const EdgeInsets.symmetric(horizontal: RubricSpace.s2),
      leading: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 32),
        child: Text(
          '${surah.index}',
          textAlign: TextAlign.end,
          style: RubricText.label.copyWith(
            color: c.inkSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      title: Text(
        names.of(surah.index),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: selected ? RubricText.label.weighted(500) : null,
      ),
      subtitle: Text(context.l10n.ayahCount(surah.ayahCount)),
      // In Arabic the title already is the Arabic name.
      // It echoes the title: with large system text it grows a little, then
      // shrinks to fit, so the title always keeps its room.
      trailing: names.isArabic
          ? null
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.3),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  surah.nameAr,
                  textDirection: TextDirection.rtl,
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                  style:
                      RubricText.surahAr.copyWith(fontSize: 22, height: 1.4, color: selected ? c.ink : c.inkUpcoming),
                ),
              ),
            ),
      onTap: onTap,
    );
  }
}
