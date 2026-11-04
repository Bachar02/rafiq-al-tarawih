import 'package:flutter/material.dart';

import '../../app/components/quran_text.dart';
import '../../app/theme.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';

/// A surah's opening inside the continuous text: its Arabic name, a quiet
/// meta line, and the basmala (not for 1 and 9).
class SurahHeader extends StatelessWidget {
  const SurahHeader({super.key, required this.quran, required this.surah, required this.names, this.scale = 1});

  final Quran quran;
  final Surah surah;
  final SurahNames names;

  /// The user's Quran text size.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final basmala = basmalaFor(quran, surah);
    return Padding(
      padding: EdgeInsets.only(top: surah.index == 1 ? RubricSpace.s4 : RubricSpace.s8, bottom: RubricSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            label: 'Surah ${names.of(surah.index)}, ${surah.index}',
            excludeSemantics: true,
            child: Column(
              children: [
                Text(
                  surah.nameAr,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: RubricText.surahAr.copyWith(fontSize: 30, color: c.ink),
                ),
                const SizedBox(height: RubricSpace.s1),
                Text(
                  '${names.of(surah.index)} · ${surah.index} · ${surah.ayahCount} ayahs',
                  textAlign: TextAlign.center,
                  style: RubricText.caption.copyWith(color: c.inkSecondary),
                ),
              ],
            ),
          ),
          if (basmala != null) ...[
            const SizedBox(height: RubricSpace.s2),
            Basmala(text: basmala, scale: scale),
          ],
        ],
      ),
    );
  }
}

/// Where a juz, hizb quarter or page begins: a hairline with a caption,
/// placed before the ayah (or surah header) it starts with.
class DivisionMark extends StatelessWidget {
  const DivisionMark({super.key, required this.label});

  final String label;

  /// The caption for [verseId], or null if it starts no page, juz or quarter.
  /// Verse 1 starts everything and needs no mark.
  static String? labelFor(Quran quran, int verseId) {
    if (verseId == 1) return null;
    final page = quran.pages.isStart(verseId);
    final quarter = quran.quarters.isStart(verseId);
    if (!page && !quarter) return null;
    final parts = <String>[];
    if (quran.juzs.isStart(verseId)) {
      parts.add('Juz ${quran.juzOf(verseId)}');
    } else if (quarter) {
      parts.add(hizbLabel(quran.quarters.of(verseId)));
    }
    if (page) parts.add('Page ${quran.pageOf(verseId)}');
    return parts.join(' · ');
  }

  /// Hizb quarter [quarter] (1..240) as read: "Hizb 3", "¼ Hizb 3", "½ Hizb 3", "¾ Hizb 3".
  static String hizbLabel(int quarter) {
    final hizb = (quarter - 1) ~/ 4 + 1;
    const fraction = ['', '¼ ', '½ ', '¾ '];
    return '${fraction[(quarter - 1) % 4]}Hizb $hizb';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RubricSpace.s2),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.hairline)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RubricSpace.s3),
            child: Text(label, style: RubricText.caption.copyWith(color: c.inkSecondary)),
          ),
          Expanded(child: Divider(color: c.hairline)),
        ],
      ),
    );
  }
}
