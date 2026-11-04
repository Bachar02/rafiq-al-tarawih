import 'package:flutter/material.dart';

import '../../data/quran.dart';
import '../../data/surah_names.dart';
import '../theme.dart';

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
      leading: SizedBox(
        width: 32,
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
      subtitle: Text('${surah.ayahCount} ayahs'),
      trailing: Text(
        surah.nameAr,
        textDirection: TextDirection.rtl,
        style: RubricText.surahAr.copyWith(fontSize: 22, height: 1.4, color: selected ? c.ink : c.inkUpcoming),
      ),
      onTap: onTap,
    );
  }
}
