import 'package:flutter/material.dart';

import '../../app/components/quran_text.dart';
import '../../app/theme.dart';
import '../../data/quran.dart';
import '../../data/surah_names.dart';
import '../../l10n/l10n.dart';

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
    final l = context.l10n;
    final basmala = basmalaFor(quran, surah);
    return Padding(
      padding: EdgeInsets.only(top: surah.index == 1 ? RubricSpace.s4 : RubricSpace.s8, bottom: RubricSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            label: l.semSurahHeader(names.of(surah.index), surah.index),
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
                  names.isArabic
                      ? '${surah.index} · ${l.ayahCount(surah.ayahCount)}'
                      : l.surahHeaderMeta(names.of(surah.index), surah.index, l.ayahCount(surah.ayahCount)),
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
  static String? labelFor(Quran quran, int verseId, AppLocalizations l) {
    if (!marks(quran, verseId)) return null;
    final page = quran.pages.isStart(verseId);
    final quarter = quran.quarters.isStart(verseId);
    final parts = <String>[];
    if (quran.juzs.isStart(verseId)) {
      parts.add(l.juzNumber(quran.juzOf(verseId)));
    } else if (quarter) {
      parts.add(hizbLabel(l, quran.quarters.of(verseId)));
    }
    if (page) parts.add(l.pageNumber(quran.pageOf(verseId)));
    return parts.join(' · ');
  }

  /// [verseId] begins a page or a hizb quarter (so a juz too), and gets a
  /// mark. Verse 1 begins everything and needs none.
  static bool marks(Quran quran, int verseId) =>
      verseId != 1 && (quran.pages.isStart(verseId) || quran.quarters.isStart(verseId));

  /// Hizb quarter [quarter] (1..240) as read: "Hizb 3", "¼ Hizb 3", "½ Hizb 3", "¾ Hizb 3".
  static String hizbLabel(AppLocalizations l, int quarter) {
    final hizb = (quarter - 1) ~/ 4 + 1;
    return switch ((quarter - 1) % 4) {
      0 => l.hizbStart(hizb),
      1 => l.hizbQuarter(hizb),
      2 => l.hizbHalf(hizb),
      _ => l.hizbThreeQuarters(hizb),
    };
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
